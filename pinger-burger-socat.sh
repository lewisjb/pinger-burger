#!/bin/sh
# Written by lewisjb

DIRECTORY="devices" # Location to store data

SECONDS_IN_A_DAY=$((60*60*24))

export PINGER_BURGER_OUTPUT="" # Stores the outgoing message

# Checks dependencies
check_deps() {
  # Check they have date
  if [ ! "`command -v date`" ]; then
    echo "Script required GNU 'date'" >&2
    exit 1
  fi

  # Check they have GNU date
  if [ -z "`date --help | grep GNU`" ]; then
    echo "You have 'date', but it isn't GNU 'date'" >&2
    exit 1
  fi
}

# Does sever setup
setup() {
  # Create the folder to store data
  if [ ! -d "$DIRECTORY" ]; then
    mkdir "$DIRECTORY"
    if [ ! $? ]; then
      echo "Script unable to create $DIRECTORY" >&2
      exit 1
    fi
  fi
}

# Converts line-separated strings into JSON format
# Args: lineSeparatedStrings
convert_to_json_list() {
  JSON="[" # Start the JSON
  # Separate by newline
  IFS='
  '
  # Add to JSON
  for item in $1; do
    JSON="$JSON\n\t\"$item\","
  done

  # Remove last ','
  if [ "${JSON: -1}" == "," ]; then
    JSON=${JSON: : -1}
  fi

  # End the JSON
  JSON="$JSON\n]"

  echo $JSON
}

# Converts date into epoch
# date can either be YYYY-MM-DD or epoch
# Args: date
convert_to_epoch() {
  # Seeing as there is already RegEx to contrain between the two, just check
  # for one.
  if (echo $1 | grep -Eq "^[0-9]+$") ; then
    # Epoch, return as-is
    echo $1
  else
    # YYYY-MM-DD, convert to epoch
    echo `date -u -d "$1" +%s`
  fi
}

# Gets the pings from a device in a time period
# Args: deviceId epochFrom epochTo
get_pings_for_device() {
  FILTERED=''
  IFS='
  '
  if [ -e "$DIRECTORY/$1" ]; then
    for ping in `cat $DIRECTORY/$1`; do
      # >= from and < to
      if [ "$ping" -ge $2 ] && [ "$ping" -lt $3 ]; then
        FILTERED="$FILTERED$ping\n"
      fi
    done
  fi

  # Remove last '\n'
  if [ ! -z "$FILTERED" ]; then
    FILTERED=${FILTERED: : -2}
  fi

  echo -e $FILTERED
}

# Gets the pings from all devices in a time period
# Args: epochFrom epochTo
get_pings_for_all() {
  RESPONSE='{'
  IFS='
  '
  for device in `ls $DIRECTORY`; do
    RESPONSE="$RESPONSE\n\t\"$device\": ["
    for ping in `get_pings_for_device $device $1 $2`; do
      RESPONSE="$RESPONSE\n\t\t$ping,"
    done

    # Remove the last ','
    if [ "${RESPONSE: -1}" == "," ]; then
      RESPONSE=${RESPONSE: : -1}
    fi

    RESPONSE="$RESPONSE\n\t],"
  done

  # Remove the last ','
  if [ "${RESPONSE: -1}" == "," ]; then
    RESPONSE=${RESPONSE: : -1}
  fi
  RESPONSE="$RESPONSE\n}"

  echo -e $RESPONSE
}

# Handles GET requests
# Args: relativeURL
handle_get_request() {
  REQ_RESPONSE=""
  if (echo $1 | grep -q "\/devices") ; then
    # /devices
    REQ_RESPONSE=$(convert_to_json_list "`ls $DIRECTORY`")
  elif (echo $1 | grep -Eq "\/.*?\/([0-9]+|[0-9]{4}-[0-9]{2}-[0-9]{2})\/\
([0-9]+|[0-9]{4}-[0-9]{2}-[0-9]{2})") ; then
    # /:deviceId/:from/:to
    DEVICE_ID=`echo $1 | cut -d '/' -f2`
    UTC_DATE_FROM=`echo $1 | cut -d '/' -f3`
    UTC_DATE_TO=`echo $1 | cut -d '/' -f4`
    FILTER_FROM=`convert_to_epoch $UTC_DATE_FROM`
    FILTER_TO=`convert_to_epoch $UTC_DATE_TO`

    if [ "$DEVICE_ID" == "all" ]; then
      # All devices
      PINGS=`get_pings_for_all $FILTER_FROM $FILTER_TO`
      REQ_RESPONSE="$PINGS"
    else
      # Specific device
      PINGS=`get_pings_for_device $DEVICE_ID $FILTER_FROM $FILTER_TO`
      REQ_RESPONSE=`convert_to_json_list "$PINGS"`
    fi
  elif (echo $1 | grep -Eq "\/.*?\/[0-9]{4}-[0-9]{2}-[0-9]{2}") ; then
    # /:deviceId/:date
    DEVICE_ID=`echo $1 | cut -d '/' -f2`
    UTC_DATE=`echo $1 | cut -d '/' -f3`
    FILTER_FROM=`convert_to_epoch $UTC_DATE`
    FILTER_TO=$(($FILTER_FROM + $SECONDS_IN_A_DAY))

    if [ "$DEVICE_ID" == "all" ]; then
      # All devices
      PINGS=`get_pings_for_all $FILTER_FROM $FILTER_TO`
      REQ_RESPONSE="$PINGS"
    else
      # Specific device
      PINGS=`get_pings_for_device $DEVICE_ID $FILTER_FROM $FILTER_TO`
      REQ_RESPONSE=`convert_to_json_list "$PINGS"`
    fi
  else
    # Invalid URL
    PINGER_BURGER_OUTPUT="`printf "HTTP/1.1 404 Not Found\nLocation: $1\n\n"`"
    return
  fi
  PINGER_BURGER_OUTPUT="$(printf "HTTP/1.1 200 OK\nLocation: $1\n\n$REQ_RESPONSE\n")"
}

# Handles POST requests
# Args: relativeURL
handle_post_request() {
  REQ_STATUS="200 OK"
  if (echo $1 | grep -q "\/clear_data") ; then
    # /clear_data
    if [ ! -z "`ls $DIRECTORY`" ]; then
      rm $DIRECTORY/*
    fi
  elif (echo $1 | grep -Eq "\/.*?\/[0-9]+") ; then
    # /:deviceId/:epochTime
    DEVICE_ID=$(echo "$1" | cut -d '/' -f2)

    # Doesn't exist yet
    if [ ! -e "$DIRECTORY/$DEVICE_ID" ] ; then
      touch "$DIRECTORY/$DEVICE_ID"
    fi

    # Add epoch
    echo $(echo "$1" | cut -d '/' -f3) >> "$DIRECTORY/$DEVICE_ID"
  else
    REQ_STATUS="404 Not Found"
    return
  fi
  PINGER_BURGER_OUTPUT="`printf "HTTP/1.1 $REQ_STATUS\nLocation: $1\n\n"`"
}

check_deps
setup

# Get the request header
read header
header=$(echo "$header" | tr -d '[\r\n]')

# Ignore the rest
while read line ; do
  #:
  line=$(echo "$line" | tr -d '[\r\n]')
  if [ -z "$line" ] ; then
    break
  fi
done

# Validate request
if ! (echo "$header" | grep -Eq '^(GET|POST) /') ; then
  # Invalid message
  echo "HTTP/1.1 400 Bad Request"
  continue
fi

# Handle request
REQ_TYPE=`echo $header | cut -d ' ' -f1`
REQ_LOC=`echo $header | cut -d ' ' -f2`
if [ "$REQ_TYPE" == "GET" ]; then
  handle_get_request $REQ_LOC
else
  handle_post_request $REQ_LOC
fi

printf "$PINGER_BURGER_OUTPUT"
