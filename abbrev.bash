#!/bin/bash
# New in Version
# [2020-08-01] 1.1 - Can apply abbreviations to existing SNOW records
#                  - Enforce minimum 3 characters to be a candidate
#
VER="1.1"
STRICT_MODE=1
SNOW_SERVER="cdw.service-now.com"
#SNOW_SERVER="cdwdev.service-now.com"

help_msg () {
        echo ; echo "Usage: $0 [-s] [-V] [-f] -c \"COMPANY NAME\""
        echo ; echo "Where:"
        echo "  -s = Disable 'Strict Mode'"
        echo "  -V = Verbose (lists why potential abbreviations were rejected)"
        echo "  -f = Only return first qualifying candidate [See warning below]"
        echo "  -c = Name of company to abbreviate" ; echo
        echo "The script will ask for a ServiceNow user name and password." ; echo
        echo "Purpose:" ; echo
        echo "This script generates an abbreviation for a company name, but first checks that the abbreviation"
        echo "is not found in Urban Dictionary or already in use in ServiceNow." ; echo
        echo "If a company record is found in ServiceNow and it has an abbreviation already, the script will stop." ; echo
        echo "If Strict Mode is disabled, matches found in Urban Dictionary will be flagged with an asterisk,"
        echo "but still listed as possible options." ; echo
        echo "If '-f' is used, the script will return only the first qualifying abbreviation to the company record in"
        echo "ServiceNow (if one exists).  This can be problematic if 'Strict Mode' is also disabled."; echo
}

test_cred () {
        #Make sure the credentials provided work
        ACCT_CHECK="$(curl -su "$AUTH_STRING" -X GET -H "Content-Type: application/json" "https://${SNOW_SERVER}/api/now/table/core_company?sysparm_query=u_abbreviation%3DCDW&sysparm_fields=u_abbreviation&sysparm_limit=1")"
        [[ "$ACCT_CHECK" =~ .*"User Not Authenticated".* ]] && echo && echo "Failed to authenticate" && echo && exit 1
}

check_already_exists () {
        CHECK_COMPANY="$(echo "${COMPANY// /%20}")"
        CHECK_COMPANY="$(echo "${CHECK_COMPANY//&/%26}")"
        # if company record already has an abbreviation, stop
        SNOW_DONE="$(curl -su "$AUTH_STRING" -X GET -H "Content-Type: application/json" "https://${SNOW_SERVER}/api/now/table/core_company?sysparm_query=name%3D${CHECK_COMPANY}&sysparm_fields=u_abbreviation&sysparm_limit=1" | python -mjson.tool | grep u_abbreviation | awk -F"\"" {'print $4'})"
        [[ $SNOW_DONE ]] && echo "An abbreviation ($SNOW_DONE) already exists for $COMPANY" && echo && exit 0
        SYS_ID="$(curl -su "$AUTH_STRING" -X GET -H "Content-Type: application/json" "https://${SNOW_SERVER}/api/now/table/core_company?sysparm_query=name%3D${CHECK_COMPANY}&sysparm_fields=sys_id&sysparm_limit=1" | python -mjson.tool | grep sys_id | awk -F "\"" {'print $4'})"
        [[ $SYS_ID ]] && CAN_UPDATE=1
}

post_to_snow () {
        [[ ! $CAN_UPDATE ]] && echo "Unable to update ServiceNow" && return
        JSON="{ 'u_abbreviation': '$(echo $ABBREV_CHOICE)' }"
        RESULT="$(curl -su "$AUTH_STRING" -X PUT -H "Content-Type: application/json" -H 'Content-Type: application/json' "https://${SNOW_SERVER}/api/now/table/core_company/${SYS_ID}" -d "$JSON" | python -mjson.tool | grep u_abbreviation | awk -F "\"" {'print $4'})"
        echo 
        [[ "$RESULT" == "$ABBREV_CHOICE" ]] && echo "Successfully applied $ABBREV_CHOICE to $COMPANY" || echo "Failed to update $COMPANY record"
}

check_urban_dictionary () {
        # Check Urban Dictionary API
        UD_MATCH=$(curl -sk -X GET -H "Content-Type: application/json" https://api.urbandictionary.com/v0/define?term=$1 | python -mjson.tool  |grep "\"word\"" | wc -l)
        [[ $UD_MATCH -gt 0 ]] && UD_FLAG=1
        [[ $VERBOSE && $UD_FLAG ]] && echo " - $1 found in Urban Dictionary"
}

check_snow () {
        # If some other company alrady has this abbreviation, skip it
        SN_MATCH=$(curl -su "$AUTH_STRING" -X GET -H "Content-Type: application/json" "https://${SNOW_SERVER}/api/now/table/core_company?sysparm_query=u_abbreviation%3D${1}&sysparm_limit=1" | python -mjson.tool 2>/dev/null | grep "u_abbreviation" | awk -F"\"" {'print $4'}) 
        [[ $SN_MATCH ]] && SN_FLAG=1
        [[ $VERBOSE && $SN_FLAG ]] && echo " - $1 already in use in ServiceNow"
}

eval_candidate () {
        #Pause to not spam others with requests
        #Must have minimum 3 characters to be a candidate
        [[ ${#1} -lt 3 ]] && return
        sleep 2
        check_snow $1
        [[ ! $SN_FLAG ]] && check_urban_dictionary $1
        # Already in use, skip this selection
        [[ $SN_FLAG ]] && unset SN_FLAG && return
        # If strict mode is disabled, add an * to the candidate
        if [[ $STRICT_MODE ]] ; then
                [[ ! $UD_FLAG ]] && CANDIDATES+=( "$1" )
        else
                [[ ! $UD_FLAG ]] && CANDIDATES+=( "$1" ) || CANDIDATES+=( "${1}*")
        fi
        unset UD_FLAG 
}

check_first_vowel () {
        # If the first letter of the first word in the company name is a vowel, then vowels are probably too important to remove
        VOWELS=( "A" "E" "I" "O" "U" )
        VOWEL_CHECK="${CUST_NAME[0]:0:1}"
        for x in ${VOWELS[@]} ; do
                [[ "$VOWEL_CHECK" == "$x" ]] && SKIP=1
        done
        unset x
}

get_first3_to_5 () {
        PASSED_VAR="$1"
        COUNT=3
        while [ $COUNT -le 5 ] ; do
                CHECK_VAL+=("$(echo "${PASSED_VAR:0:$COUNT}")")
                ((COUNT++))
        done ; unset COUNT
}

remove_vowels () {
        check_first_vowel
        [[ $SKIP ]] && unset SKIP && return
        VOWEL_FREE="$(echo "${CUST_NAME[0]}" | sed 's/[AEIOU]//g')"
        get_first3_to_5 $VOWEL_FREE
}

two_word_adds () {
        x=2 ; while [ $x -lt 5 ] ; do
                CHECK_VAL+=("$(echo ${CUST_NAME[0]:0:1})$(echo "${CUST_NAME[1]:0:${x}}")")
                CHECK_VAL+=("$(echo ${CUST_NAME[0]:0:${x}})$(echo "${CUST_NAME[1]:0:1}")")
                ((x++))
        done  
        x=1 ; while [ $x -lt 4 ] ; do
                CHECK_VAL+=("$(echo ${CUST_NAME[0]:0:2})$(echo "${CUST_NAME[1]:0:${x}}")")
                CHECK_VAL+=("$(echo ${CUST_NAME[0]:0:${x}})$(echo "${CUST_NAME[1]:0:2}")")
                ((x++))
        done
        x=1 ; while [ $x -lt 3 ] ; do
                CHECK_VAL+=("$(echo ${CUST_NAME[0]:0:3})$(echo "${CUST_NAME[1]:0:${x}}")")
                CHECK_VAL+=("$(echo ${CUST_NAME[0]:0:${x}})$(echo "${CUST_NAME[1]:0:3}")")
                ((x++))
        done ; unset x
}

get_initials () {
        for x in ${CUST_NAME[@]} ; do
                INITIALS="${INITIALS}$(echo "${x:0:1}")"
        done ; unset x
        CHECK_VAL+=("$INITIALS")
}

glom_no_vowels () {
        #Remove spaces from company name, remove vowels and process
        check_first_vowel
        [[ $SKIP ]] && unset SKIP && return
        for x in ${CUST_NAME[@]} ; do
                GLOM="${GLOM}$(echo "$x")"
        done ; unset x
        CUST_NAME="$(echo "$GLOM" | sed 's/[AEIOU]//g')"
        if [ $(echo "${#CUST_NAME}") -gt 5 ] ; then
                get_first3_to_5 $CUST_NAME
        else
                CHECK_VAL+="$CUST_NAME"
        fi
}

while getopts "c:sfhVv?" opt ; do
        case $opt in
                "c") COMPANY="$OPTARG" ;;
                "s") unset STRICT_MODE ;;
                "f") POST_FIRST=1 ;;
                "h" | "?") help_msg ; exit 0 ;;
                "V") VERBOSE=1 ;;
                "v") echo "$0, version $VER" ; echo ; exit 0 ;;
                *) echo "Illegal option" ; help_msg ; exit 1 ;;
        esac
done

if [[ ! $COMPANY ]] ; then
        echo "No company name provided" ; echo
        while [ ! "$COMPANY" ] ; do
                printf "Please provide a company name: "
                read COMPANY
        done ; echo
fi
while [ ! $SNOW_USER ] ; do printf "ServiceNow User Name: " ; read SNOW_USER ; done
while [ ! $SNOW_PASS ] ; do stty -echo ; printf "ServiceNow Password: " ; read SNOW_PASS ; done ; stty echo  ; echo
AUTH_STRING="${SNOW_USER}:${SNOW_PASS}"
test_cred
check_already_exists

CUST_NAME=( $COMPANY )
# Remove special characters and capitalize
COUNT=0
while [ $COUNT -lt ${#CUST_NAME[@]} ] ; do
        CUST_NAME[$COUNT]="$(echo "${CUST_NAME[$COUNT]}" | tr -dc '[:alnum:]\n\r' | tr a-z A-Z)"
        ((COUNT++))
done ; unset COUNT
# Remove superfluous words
IGNORE=( "INC" "LTD" "AND" "A" "THE" "OF" "LLP" "LLC" )
for y in ${IGNORE[@]} ; do
        for i in "${!CUST_NAME[@]}" ; do
                [[ ${CUST_NAME[i]} = $y ]] && unset 'CUST_NAME[$i]'
        done
done ; unset y i
# Remove empty array members
for i in "${!CUST_NAME[@]}" ; do
        [[ "${CUST_NAME[i]}" != "" ]] && FIX_GAPS+=( "${CUST_NAME[i]}" )
done
CUST_NAME=("${FIX_GAPS[@]}")
unset FIX_GAPS i
[[ $VERBOSE ]] && echo && echo "Evaluating ${CUST_NAME[@]}" 

# Create potential abbreviations
get_first3_to_5 $CUST_NAME
remove_vowels
if [ ${#CUST_NAME[@]} -ge 2 ] ; then
        two_word_adds ; glom_no_vowels
fi
if [ ${#CUST_NAME[@]} -gt 2 ] ; then
        get_initials
        #2-2-1
        CHECK_VAL+=("$(echo "${CUST_NAME[0]:0:2}${CUST_NAME[1]:0:2}${CUST_NAME[2]:0:1}")")
        #2-1-2
        CHECK_VAL+=("$(echo "${CUST_NAME[0]:0:2}${CUST_NAME[1]:0:1}${CUST_NAME[2]:0:2}")")
        #1-2-2
        CHECK_VAL+=("$(echo "${CUST_NAME[0]:0:1}${CUST_NAME[1]:0:2}${CUST_NAME[2]:0:1}")")
        #3-1-1
        CHECK_VAL+=("$(echo "${CUST_NAME[0]:0:3}${CUST_NAME[1]:0:1}${CUST_NAME[2]:0:1}")")
        #1-1-3
        CHECK_VAL+=("$(echo "${CUST_NAME[0]:0:1}${CUST_NAME[1]:0:1}${CUST_NAME[2]:0:3}")")
        #1-3-1
        CHECK_VAL+=("$(echo "${CUST_NAME[0]:0:1}${CUST_NAME[1]:0:3}${CUST_NAME[2]:0:1}")")
fi
# Remove duplicates and check if appropriate
CHECK_VAL=( $(printf "%s\n" "${CHECK_VAL[@]}" | sort -u | tr '\n' ' ') )
echo
[[ ! $VERBOSE ]] && echo -n "Evaluating ${#CHECK_VAL[@]} candidates " || echo "Evaluating ${#CHECK_VAL[@]} candidates" 
for CHECK in ${CHECK_VAL[@]} ; do [[ ! $VERBOSE ]] && echo -n "." ; eval_candidate $CHECK ; done
if [ $VERBOSE ] ; then
        echo 
else
        echo && echo
fi
#Print results, if any
if [ ${#CANDIDATES[@]} -gt 0 ] ; then
        # If auto-post is off, present user with candidates, otherwise return first candidate
        if [[ ! $POST_FIRST ]] ; then
                echo "Candidates:"
                CAND=0
                while [ $CAND -lt ${#CANDIDATES[@]} ] ; do
                        [[ ! $CAN_UPDATE ]] && echo " - ${CANDIDATES[$CAND]}" || echo " ${CAND}. ${CANDIDATES[$CAND]}"
                        ((CAND++))
                done
                [[ $CAN_UPDATE ]] && echo && while [ ! $ABBREV_CHOICE ] ; do 
                        printf "Your pick ['q' to cancel]: " 
                        read ABBREV_CHOICE 
                        [[ "$ABBREV_CHOICE" == "q" ]] && echo && exit 0
                        [[ "${CANDIDATES[$ABBREV_CHOICE]}" == "" ]] && unset ABBREV_CHOICE
                done
                ABBREV_CHOICE="$(echo "${CANDIDATES[$ABBREV_CHOICE]//\*}")"
                [[ $ABBREV_CHOICE ]] && post_to_snow
        else
                [[ ! $CAN_UPDATE ]] && echo "Result: $(echo "${CANDIDATES[0]}")" || ABBREV_CHOICE="${CANDIDATES[0]//\*}" && post_to_snow
        fi
else
        echo "No suitable abbreviations found."
fi
echo
