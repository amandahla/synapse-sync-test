#!/usr/bin/env bash

export USER1_NAME="apple2"
export USER2_NAME="grape"
export USER1_PW="user1"
export USER2_PW="user2"

if [ -z $HOMESERVER ]; then
  echo "Please ensure HOMESERVER environment variable is set to the IP or hostname of the homeserver."
  exit 1
fi

echo "Waiting for homeserver to be available... (GET http://$HOMESERVER/_matrix/client/v3/login)"

while ! curl -XGET "http://$HOMESERVER/_matrix/client/v3/login" >/dev/null 2>/dev/null; do
  sleep 2
done

echo "Homeserver is up."

# create users

curl -fS --retry 3 -XPOST -d "{\"username\":\"$USER1_NAME\", \"password\":\"$USER1_PW\", \"inhibit_login\":true, \"auth\": {\"type\":\"m.login.dummy\"}}" "http://$HOMESERVER/_matrix/client/r0/register"
curl -fS --retry 3 -XPOST -d "{\"username\":\"$USER2_NAME\", \"password\":\"$USER2_PW\", \"inhibit_login\":true, \"auth\": {\"type\":\"m.login.dummy\"}}" "http://$HOMESERVER/_matrix/client/r0/register"

usertoken1=$(curl -fS --retry 3 "http://$HOMESERVER/_matrix/client/r0/login" -H "Content-Type: application/json" -d "{\"type\": \"m.login.password\", \"identifier\": {\"type\": \"m.id.user\",\"user\": \"$USER1_NAME\"},\"password\":\"$USER1_PW\"}" | jq -r '.access_token')
usertoken2=$(curl -fS --retry 3 "http://$HOMESERVER/_matrix/client/r0/login" -H "Content-Type: application/json" -d "{\"type\": \"m.login.password\", \"identifier\": {\"type\": \"m.id.user\",\"user\": \"$USER2_NAME\"},\"password\":\"$USER2_PW\"}" | jq -r '.access_token')


# get usernames' mxids
mxid1=$(curl -fS --retry 3 "http://$HOMESERVER/_matrix/client/r0/account/whoami" -H "Authorization: Bearer $usertoken1" | jq -r .user_id)
mxid2=$(curl -fS --retry 3 "http://$HOMESERVER/_matrix/client/r0/account/whoami" -H "Authorization: Bearer $usertoken2" | jq -r .user_id)

# setting the display name to username
curl -fS --retry 3 -XPUT -d "{\"displayname\":\"$USER1_NAME\"}" "http://$HOMESERVER/_matrix/client/v3/profile/$mxid1/displayname" -H "Authorization: Bearer $usertoken1"
curl -fS --retry 3 -XPUT -d "{\"displayname\":\"$USER2_NAME\"}" "http://$HOMESERVER/_matrix/client/v3/profile/$mxid2/displayname" -H "Authorization: Bearer $usertoken2"
echo "Set display names"

: '
for ((i=1; i<=100; i++)); do
  # Append index number to USER2_NAME
  USER2_NAME_WITH_INDEX="${USER2_NAME}_${i}"
  # create new room to invite user too
  roomID=$(curl --retry 3 --silent --fail -XPOST -d "{\"name\":\"$USER2_NAME_WITH_INDEX\", \"is_direct\": true}" "http://$HOMESERVER/_matrix/client/r0/createRoom?access_token=$usertoken2" | jq -r '.room_id')
  echo "Created room '$roomID'"
  # send message in created room
  curl --retry 3 --fail --silent -XPOST -d '{"msgtype":"m.text", "body":"joined room successfully"}' "http://$HOMESERVER/_matrix/client/r0/rooms/$roomID/send/m.room.message?access_token=$usertoken2"
  echo "Sent message"
  curl -fS --retry 3 -XPOST -d "{\"user_id\":\"$mxid1\"}" "http://$HOMESERVER/_matrix/client/r0/rooms/$roomID/invite?access_token=$usertoken2"
  echo "Invited $USER1_NAME"
done
'

# sync
curl -fS -o /tmp/output-sync -w 'Total: %{time_total}s\n' --retry 3 -XGET "http://$HOMESERVER/_matrix/client/r0/sync?access_token=$usertoken2"
sync_response=$(cat /tmp/output-sync)

# Count items in "join," "invite," and "leave" categories
join_count=$(echo "$sync_response" | jq -r '.rooms.join | length')
invite_count=$(echo "$sync_response" | jq -r '.rooms.invite | length')
leave_count=$(echo "$sync_response" | jq -r '.rooms.leave | length')
response_size=$(echo "$sync_response" | wc -c)

# Display the counts
echo "Join count: $join_count"
echo "Invite count: $invite_count"
echo "Leave count: $leave_count"
echo "Response size: $response_size bytes"

# sync
echo "PROXY"
curl -fS -o /tmp/output-sync -w 'Total: %{time_total}s\n' --retry 3 -XGET "http://$HOMESERVER/_matrix/client/unstable/org.matrix.msc3575/sync?access_token=$usertoken2"
sync_response=$(cat /tmp/output-sync)

# Count items in "join," "invite," and "leave" categories
join_count=$(echo "$sync_response" | jq -r '.rooms.join | length')
invite_count=$(echo "$sync_response" | jq -r '.rooms.invite | length')
leave_count=$(echo "$sync_response" | jq -r '.rooms.leave | length')
response_size=$(echo "$sync_response" | wc -c)

# Display the counts
echo "Join count: $join_count"
echo "Invite count: $invite_count"
echo "Leave count: $leave_count"
echo "Response size: $response_size bytes"
