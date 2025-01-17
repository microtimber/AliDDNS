#!/bin/bash

# @author Bosco.Liao
# @version 1.2.0
#
# AliDDNS:
# 支持指定域名下解析记录的更新和添加，现用于群晖NAS的DDNS，运行情况稳定。
# 如使用中发现问题，可反馈给本人：bosco_liao@126.com
#
# Usage:
#   ./aliddns.sh [OPTION]
# Options:
#   -d, --domain    Domain Name (required)
#   -h, --host      Host, default: @
#   -t, --type      Type, default: A
#   -v, --value     Value, default: IPv4(automatically detect)
#   -l, --ttl       TTL, default: 600s
# 
# eg: 
#   1) ./aliddns.sh -d example.com -h @ -h www 
#   
#   2) ./aliddns.sh -d example.com -h \* -t CNAME -v abc.sample.com -l 60
#

#==============================Settings===============================
#
#====================================================================

access_key_id=""
access_key_secret=""

#==============================Functions=============================
#
#====================================================================

# getIpv4 $ipv4_api_store
getIpv4() {
    local apis=($1)
    local index=0
    if [ $# -eq 2 ]; then
        index=$2
    fi
    local api="${apis[$index]}"
    # echo -e "The external network API currently in use is: $api"
    local max=`expr ${#apis[@]} - 1`
    local ip=`curl -sL --connect-timeout 3 -m 5 "$api"`
    if [[ -z "$ip" && $max -gt $index ]]; then
        let index++
        getIpv4 "${apis[*]}" $index
    else
        echo -n "$ip"
    fi
}

die () {
    echo $1
}

# getIpv6 of local machine
getIpv6() {
    ipv6s=`ip -6 addr|grep global|awk -F/ "{print \\$1}"|awk "{print \\$NF}"` || die "$ipv6"

    for ipv6 in $ipv6s
    do
      #ipv6 = $ipv6
      break
    done

    echo -n "$ipv6"

}

# doGet Action Api_Args
doGet() {
    execRequest 'GET' $1 $2
}

# doPost Action Api_Args
doPost() {
    execRequest 'POST' $1 $2
}

# execRequest HttpMethod Action Api_Args
execRequest() {
    local timestamp=`date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"`
    local nonce="`date +'%s'`$RANDOM"
    local argstr="AccessKeyId=$access_key_id&Action=$2&$3&Format=json&SignatureMethod=HMAC-SHA1&SignatureNonce=$nonce&SignatureVersion=1.0&Timestamp=$timestamp&Version=2015-01-09"

    if test "POST" = "$1"
    then
        curl -s -w " | \"HttpStatusCode\":%{http_code}" "$gateway" -X POST -d "$argstr&Signature=`getSignature $1 $argstr`"
    else
        curl -s -w " | \"HttpStatusCode\":%{http_code}" "$gateway?$argstr&Signature=`getSignature $1 $argstr`"
    fi
}

# sign $HttpMethod $StringToSign
getSignature() {
    if test -z "$2"
    then
        echo "ERROR: The string to be signed was not found." 1>&2
        exit
    fi
    # Not match API sort result, Use method 'composeStringToSign' instead.
    #local sign_args=$(echo $2 | tr '&' '\n'| sort | awk '{printf "%s&", $0}' | sed '$s/.$//')
    local sign_args=`composeStringToSign "$2"`
    local sign_str="$1&`urlEncode '/'`&`urlEncode $sign_args`"

    # Hash-SHA1 --> Base64 --> string
    local signature=$(echo -n "$sign_str" | openssl dgst -sha1 -hmac "$access_key_secret&" -binary | openssl base64)
    signature=`urlEncode $signature` # encoding required.
    echo -n "$signature"
}

urlEncode() {
    echo -n $1 | execEncode
}

execEncode() {
    local result=""
    local tempc=""
    while read -n 1 code
    do 
        case $code in
            [a-zA-Z0-9\.\-\_\~]) result="$result$code";; # don't encoding.
            *) tempc=`printf "%%%02X" "'$code"`
               result="$result$tempc";;
        esac
    done
    echo -n "$result"
}

symbolEncode() {
    if test "*" = "$1" -o "@" = "$1"
    then
        printf "%%%02X" "'$1"
    else
        echo -n "$1"
    fi
}

# bubbleSort $array_strings
bubbleSort() {
    local eles=(`echo -n "$1" | tr ' ' ' '`) # String to Array
    local len=${#eles[@]}
    local next=0
    local tmp=""
    for ((i=0;i<len-1;i++))
    do
        for ((j=0;j<len-1-i;j++))
        do
            next=$[$j + 1]
            if [ "${eles[$j]}" \> "${eles[$next]}" ]
            then
                tmp="${eles[$j]}"
                eles[$j]=${eles[$next]}
                eles[$next]=$tmp
            fi
        done
    done

    echo ${eles[@]}
}

# composeStringToSign $all_params_linked_str
composeStringToSign() {
    local ins_args="$1"
    local kvs=`echo -n $ins_args | tr '&' ' '`
    local ks=(`echo -n $ins_args | tr '&' '\n' | cut -d '=' -f 1`)
    local sorted_ks=`bubbleSort "${ks[*]}"`
    local sign_str=""
    local tmp_k=""
    for sk in $sorted_ks
    do
        for kv in $kvs
        do
            tmp_k=`echo "$kv" | cut -d '=' -f 1`
            if test "$sk" = "$tmp_k"
            then
                if test -z "$sign_str"
                then
                    sign_str="$kv"
                else
                    sign_str="$sign_str&$kv"
                fi
                break
            fi
        done
    done
    echo -n "$sign_str"
}

# diffset "${arrayA[*]}" "${arrayB[*]}"
diffset() {
    local mw="" # Matched word
    local nmw=() # Not matched word
    local src_arr=($1)
    local dest_arr=($2)

    for se in ${src_arr[@]}
    do
        if test "\"*\"" = "$se"
        then
            mw=`echo "${dest_arr[*]}" | tr ' ' '\n' | grep -w "\"\*\""`
        else
            mw=`echo "${dest_arr[*]}" | tr ' ' '\n' | grep -w "$se"`
        fi
        if test -z "$mw"
        then
            nmw+=("$se")
        fi
    done
    echo ${nmw[@]}
}

getValue() {
    grep -o '"Value":"[a-zA-Z0-9\.:\/]*"' | awk -F '":"' '{print $2}' | tr -d '"'
}

getRR() {
    grep -o '"RR":"[a-zA-Z0-9\*@]*"'| cut -d ":" -f 2 #| tr -d '"'
}

getEnText() {
    echo -n "$1" | grep -Eo "\"$2\":\"[a-zA-Z.]+\"" | cut -d ":" -f 2 | tr -d '"'
}

getNumText() {
    echo -n "$1" | grep -Eo "\"$2\":(\"?)[0-9]+(\"?)" | cut -d ":" -f 2 | tr -d '"'
}

#============================Service Impl============================
#
#====================================================================

# updateRecordValue $RecordId $Host
updateRecordValue() {
    local rid="$1"
    local host="$2"
    local data=""

    #echo -e "::"
    echo -e "Different $arg_type record [$host.$arg_domain ] with value [ $arg_value ] is updating."

    if [ 'AAAA' = $arg_type ] 
    then
        data="RecordId=$rid&RR=`symbolEncode "$host"`&Type=$arg_type&Value=`urlEncode "$arg_value"`&TTL=$arg_ttl"
    else
        data="RecordId=$rid&RR=`symbolEncode "$host"`&Type=$arg_type&Value=$arg_value&TTL=$arg_ttl"
    fi

    local result=`doPost "UpdateDomainRecord" "$data"`

    if test 200 -ne `getNumText "$result" "HttpStatusCode"`
    then
        echo "Update Record Failed: $arg_type record [ $host.$arg_domain ] with value [ $arg_value ],  Response Error: `getEnText "$result" "Code"`." 1>&2
    else
        echo "Update Record Successful: $arg_type record [ $host.$arg_domain ] with value [ $arg_value ]."
    fi
}

# addRecord $Hosts_array
addRecord() {
    local hosts="$1"
    local host=""
    local data=""
    local result=""
    for tho in $hosts
    do
        # host="${tho//\"/''}"
        host=`echo -n "$tho" | tr -d '"'`
        #echo -e "::"
        echo -e "$arg_type record [ $host.$arg_domain ] with value [ $arg_value ] is adding."

        # wrapper request data
        if [ 'AAAA' = $arg_type ] 
        then
            data="DomainName=$arg_domain&RR=`symbolEncode "$host"`&Type=$arg_type&Value=`urlEncode "$arg_value"`&TTL=$arg_ttl"
        else
            data="DomainName=$arg_domain&RR=`symbolEncode "$host"`&Type=$arg_type&Value=$arg_value&TTL=$arg_ttl"
        fi

        result=`doPost "AddDomainRecord" "$data"`

        if test 200 -ne `getNumText "$result" "HttpStatusCode"`
        then
            echo "Add Record Failed: $arg_type record [ $host.$arg_domain ] with value [ $arg_value ],  Response Error: `getEnText "$result" "Code"`." 1>&2
        else
            echo "Add Record Successful: $arg_type record [ $host.$arg_domain ] with value [ $arg_value ]."
        fi

    done
}

# Service process control.
execDDNS() {
    local records=`doGet 'DescribeDomainRecords' "DomainName=$arg_domain&TypeKeyWord=$arg_type"`
    
    if test 200 -ne `getNumText "$records" "HttpStatusCode"`
    then
        echo "Query Record Error: `getEnText "$records" "Code"`." 1>&2 
        exit
    fi

    local count=`getNumText "$records" "TotalCount"`
    if test 1 -gt $count
    then
        addRecord "${arg_hosts[*]}"
    else
        local host=""
        local value=""
        local status=""
        local recid=""
        local pos=0
        local matched_hosts=()
        local rhosts=`echo -n $records | getRR`
        local values=`echo -n $records | getValue`
        local statuses=`getEnText "$records" "Status"`
        local recids=`getNumText "$records" "RecordId"`

        for ah in ${arg_hosts[@]}
        do
            pos=1
            # host="${ah//\"/''}"
            host=`echo -n "$ah" | tr -d '"'`

            for rh in ${rhosts[@]}
            do
                status=`echo -n $statuses | cut -d ' ' -f $pos`

                if test "ENABLE" = "$status" -a "$rh" = "$ah"
                then
                    matched_hosts+=("$ah") # Records match hosts.
                    value=`echo -n $values | cut -d ' ' -f $pos`
                    recid=`echo -n $recids | cut -d ' ' -f $pos`

                    case $arg_type in
                        A) #IPv4
                            if test "$value" = "$arg_value"
                            then
                                #echo -e "::"
                                echo -e "Same $arg_type Record: [ $host.$arg_domain ] with ipv4 [ $value ] -- Don't update."
                            else
                                updateRecordValue "$recid" "$host"
                            fi
                            break;;
                        AAAA) #IPv6
                            if test "$value" = "$arg_value"
                            then
                                #echo -e "::"
                                echo -e "Same $arg_type Record: [ $host.$arg_domain ] with ipv6 [ $value ] -- Don't update."
                            else
                                updateRecordValue "$recid" "$host"
                            fi
                            break;;
                        *) # CNAME,MX,REDIRECT_URL...
                            if test "$value" = "$arg_value"
                            then
                                #echo -e "::"
                                echo -e "Same $arg_type Record: [ $host.$arg_domain ] with value [ $value ] -- Don't update."
                            else
                                updateRecordValue "$recid" "$host"
                            fi
                            break;;
                    esac
                fi
                # incr current position
                let pos++

            done
            
        done

        # Add not matched hosts.
        local not_matched_hosts=(`diffset "${arg_hosts[*]}" "${matched_hosts[*]}"`)
        addRecord "${not_matched_hosts[*]}"

    fi
}

#==============================Commons Params===========================
#
#=======================================================================

gateway="http://alidns.aliyuncs.com/"
readonly gateway

ipv4_api_store=('icanhazip.com' 'whatismyip.akamai.com' 'ip.3322.net')
readonly ipv4_api_store

extranet_ipv4=`getIpv4 "${ipv4_api_store[*]}"`
extranet_ipv6=`getIpv6`

#========================Parse parameters===============================
#
#=======================================================================
usage_tips="Argument Setting Style: \n-d  [--domain (required)]; \n-h  [--host]; \n-t  [--type]; \n-v  [--value]; \n-l  [--ttl]."
readonly usage_tips

arg_domain=""
arg_hosts=()
arg_type="A"
arg_value=""
arg_ttl=600 # seconds

getopt_args=`getopt -o d:h:t:v:l: -al domain:,host:,type:,value:,ttl: -- "$@"`
# Adjust the coordinate
eval set -- "$getopt_args"

while test -n "$1"
do 
    case "$1" in
        -d|--domain) arg_domain=$2; shift 2;;
        -h|--host) arg_hosts+=("\"$2\""); shift 2;;
        -t|--type) arg_type=`echo "$2" | tr 'a-z' 'A-Z'`; shift 2;;
        -v|--value) arg_value=$2; shift 2;;
        -l|--ttl) arg_ttl=$2; shift 2;;
        --) break;;
        *) echo -e "Error with [$1, $2], Please check it.\n$usage_tips" 1>&2; exit;;
    esac
done

#==========================Service Control==============================
#
#=======================================================================
echo -e "\n============================================================"
echo -e "Current OS: `uname -s` `uname -m` `uname -o` "
echo -e "Current Time: `date +'%Y-%m-%d %H:%M:%S'`"

# Checks aliyun api Access Key ID and Access Key Secret.
if test -z "$access_key_id" -o -z "$access_key_secret"
then
    echo "ERROR: Aliyun Access_Key_ID or Access_Key_Secret is not setted. Please setting it." 1>&2
    exit
fi

# Arg[domain] must be setted.
if test -z "$arg_domain"
then
    echo "ERROR: Please setting argument: [-d example.com | --domain example.com]." 1>&2
    exit
fi

# Check type and setting value.
if test 'A' != "$arg_type" -a 'AAAA' != "$arg_type"
then
    if test 'NS' = "$arg_type" -o 'MX' = "$arg_type" -o 'TXT' = "$arg_type" -o 'CNAME' = "$arg_type" -o 'SRV' = "$arg_type" -o 'CAA' = "$arg_type" -o 'REDIRECT_URL' = "$arg_type" -o 'FORWARD_URL' = "$arg_type"
    then
        if test -z "$arg_value"
        then
            echo "ERROR: Except for types A and AAAA, other types cannot automatically recognize the record value, please use the option: [-v | --value] to assign the value explicitly." 1>&2
            exit
        fi
    else 
        echo "ERROR: Unexpected type. Candidate type: [A, AAAA, CNAME, MX, NS, TXT, SRV, CAA, REDIRECT_URL, FORWARD_URL]." 1>&2
        exit
    fi
fi

# Default host is '@'.
if test 0 -eq ${#arg_hosts[@]}
then
    echo -e "Parameter[ Host ] was not found. Setting default host: '@'."
    arg_hosts=('"@"')
else
    arg_hosts=(`echo -n "${arg_hosts[*]}" | tr 'A-Z' 'a-z'`) # convert to lowercase
fi

# Default value is IPv4 address.
if test -z "$arg_value"
then
    case "$arg_type" in
        A) 
            echo -e "External IPv4: $extranet_ipv4 "
            arg_value="$extranet_ipv4"
            ;;
        AAAA)
            echo -e "External IPv6: $extranet_ipv6 "
            arg_value="$extranet_ipv6"
            ;;
        *) break;;
    esac

    if test -z "$arg_value" 
    then
        echo "ERROR: DNS record value must be set, please use option: [-v | --value] to set it." 1>&2
        exit
    fi

fi

# Print all setting params.
echo -e "Settting Params: {Domain: $arg_domain, Type: $arg_type, Host: [ ${arg_hosts[@]} ], Value: $arg_value, TTL: $arg_ttl}"
# Execute DDNS service
execDDNS

# end
echo -e "Completed!!!"
