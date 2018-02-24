#!/bin/sh
studnetNr=""
studnetPass=""

HOST=https://bing.com
while true; do
        while ! (curl --head --silent --connect-timeout 2 --cert-status "$HOST"  > /dev/null && sleep 10); do #if 'ping' unsuccesful attempt to reconnect
                echo "Pinging $HOST was unsucessful." >2
                echo "Reconnecting now"
                kill %1 > /dev/null 2>&1
                sleep 3
sshpass -p "$studnetPass" ssh -t -t -o StrictHostKeyChecking=no "$studnetNr"@139.18.143.253 &
                sleep 2
        done
done
