#!/bin/sh
studnetNr=""
studnetPass=""

HOST=https://bing.com
while true; do
	curl --head --silent --connect-timeout 2 "$HOST" > /dev/null
	error_code=$?

	if [ "$error_code" -gt 0 ]; then
		echo "Pinging $HOST was unsucessful." 1>&2
		echo "Reconnecting now"
		# kill 1st background job in current session, which is our (old) ssh session
		kill %1 > /dev/null 2>&1
		sleep 3
		sshpass -p "$studnetPass" ssh -t -t -o StrictHostKeyChecking=no "$studnetNr"@139.18.143.253 &
		sleep 2
	else
		sleep 10
	fi
done
