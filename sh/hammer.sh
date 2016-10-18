#!/bin/bash

timestamp_ms() {
  if which 'python' &> /dev/null; then
	  python -c 'import time; print(int(time.time()*1000))'
  else
	  date +"%s000"
  fi
}

timestamp() {
  date +"%s"
}

hammerDist() {
	local calls=${CALLS:-"$(cat)"}
	if [[ -e calls ]]; then
		calls="$(cat \"$calls\")" # I did it for the lulz
	fi

	local output_file=${OUTPUT_FILE:-/tmp/hammer.$start.dump.tsv}
	local dump_file=${DUMP_FILE:-/tmp/hammer.$start.dump.tsv}
	local run_local=${RUN_LOCAL:-0}
	local command="$(declare -f hammer)"
	command+="\n\n"
	command+="export THROTTLE_CALLS=\"${THROTTLE_CALLS}\"\n"
	command+="export THROTTLE_TIME=\"${THROTTLE_TIME}\"\n"
	command+="export CONCURRENCY=\"${CONCURRENCY}\"\n"
	command+="export OUTPUT_FILE=\"${output_file}\"\n"
	command+="export DUMP_FILE=\"${dump_file}\"\n"
	command+="export ITERATIONS=\"${ITERATIONS}\"\n"
	command+="export CALLS=\"${calls}\"\n"
	command+="CMD_PREFIX=\"${CMD_PREFIX}\"\n"

	for server in "$@"; do
		local ssh_status="$(ssh -o BatchMode=yes -o ConnectTimeout=3 \"$server\" echo ok 2>&1)"

		if [[ $ssh_status != ok ]] ; then
			echo "Error connecting to server $server: $ssh_status"
			return
		fi
	done

	for server in "$@"; do
		echo "Starting hammer on server $server"
		local server_command="$command"
		server_command+="export SERVER=${server}\n"
		server_command+="\n"
		server_command+="hammer"
		echo "ssh $server <<< \"$server_command\" &"
		return
		#ssh "$server" <<< "$server_command" &
	done

	if [[ $run_local != 0 ]]; then
		hammer
	fi

	[[ $(($(jobs -rp |wc -l))) -gt 0 ]] && echo "WAITING FOR SERVERS TO FINISH" && wait

	for server in "$@"; do
		local outfile=/tmp/$server.${output_file%*/}
		scp "$server":"$output_file" "$outfile"
		echo "Copied output file from server $server to $outfile"

		local dumpfile=/tmp/$server.${output_file%*/}
		scp "$server":"$dump_file" "$dumpfile"
		echo "Copied output file from server $server to $dumpfile"
	done
}

hammer() {
	local start=$(timestamp)
	local throttle_calls=${THROTTLE_CALLS:-0}
	local throttle_time=${THROTTLE_TIME:-60}
	local concurrency=${CONCURRENCY:-50}
	local output_file=${OUTPUT_FILE:-/tmp/hammer.$start.tsv}
	local open_output=${OPEN_OUTPUT:-0}
	local dump_file=${DUMP_FILE:-/tmp/hammer.$start.dump.tsv}
	local server=${HAMMER_SERVER:-"local"}
	local iterations=${ITERATIONS:-100}
	local calls=${CALLS:-"$(cat)"}
	if [[ -e calls ]]; then
		calls="$(cat \"$calls\")" # I did it for the lulz
	fi

	local default_prefix="curl --w '%{http_code}\t%{time_total}\t%{time_connect}\t%{time_namelookup}\t%{time_pretransfer}\t%{time_redirect}\t%{time_starttransfer}\t%{size_download}\t%{size_upload}\t%{size_request}\t%{size_header}\t%{speed_download}\t%{speed_upload}\t%{num_connects}\t%{num_redirects}\t%{redirect_url}\t%{url_effective}'"
	local cmd_prefix=${CMD_PREFIX:-$default_prefix}

	if [[ $cmd_prefix == "$default_prefix" ]]; then
		echo "ID\tHammer Server\tIndex\tStart Time (timestamp ms)\tEnd Time (timestamp ms)\tCall\tExit Code\tHTTP Code\tTotal Time (sec)\tTime To Connect (sec)\tTime for Name Lookup (sec)\tTime Pretransfer (sec)\tTime Redirected (sec)\tTime Start Transfer (sec)\tSize Downloaded (bytes)\tSize Uploaded (bytes)\tSize of Request (bytes)\tSize of Header (bytes)\tSpeed of Download (bytes/sec)\tSpeed of Upload (bytes/sec)\tNumber of Connections\tNumber of Redirects\tRedirect URL\tEffective URL" > $output_file
	else
		echo "ID\tHammer Server\tIndex\tStart Time (timestamp ms)\tEnd Time (timestamp ms)\tCall\tExit Code\tTotal Time(sec)" > $output_file
	fi

	local counter=1
	local cur_throttle_count=0
	local num_throttle=0
	declare -a pids
	echo "HAMMERING with $iterations and max $concurrency concurrency."
	if [[ $throttle_calls -gt 0 ]]; then
		echo "throttling $((throttle_calls / throttle_time)) calls/s."
	fi

	for i in $(seq 1 $iterations); do
		echo "ITERATION: $i"

		while read -r call; do

			if (( throttle_calls > 0 )); then 
				local run_time=$(($(timestamp) - start))
				throttle_count=$((run_time / throttle_time))
				local throttle_reset=$(((cur_throttle_count + 1) * throttle_time))
				# echo "RUNTIME: $run_time, CUR THROTTLE COUNT: $cur_throttle_count, THROTTLE_COUNT: $throttle_count, THROTTLE_RESET: $throttle_reset, NUM_THROTTLE: $num_throttle"

				if (( $throttle_count > $cur_throttle_count )); then
					echo "RESET THROTTLE: $throttle_count > $cur_throttle_count"
					cur_throttle_count=$throttle_count
					num_throttle=0
				fi

				if (( num_throttle >= throttle_calls )); then
					local time_to_throttle=$((throttle_reset - run_time))
					echo "THROTTLING FOR $time_to_throttle seconds"
					sleep $time_to_throttle
					num_throttle=0
				fi
			fi

			if (( $(jobs -pr | wc -l) >= $concurrency )); then
				local pid_to_wait=${pids[$((counter-concurrency))]}
				echo "WAITING FOR PID $pid_to_wait: MAX CONCURRENCY HIT: $counter"
				wait $pid_to_wait
			fi

			{
				local start_call=$(timestamp_ms)
				local index=$counter
				local local_dump=$(mktemp)
				local uuid=$(uuidgen)
				if [[ $cmd_prefix == "$default_prefix" ]]; then
					#echo "Running: $cmd_prefix -o $local_dump $call"
					local cmd_output="$(eval "$cmd_prefix -o $local_dump $call" 2> /dev/null)"
					local exit_code=$?
					local end_call=$(timestamp_ms)
					echo "$uuid\t$server\t$index\t$start_call\t$end_call\t$call\t$exit_code\t$cmd_output" >> $output_file
					echo "$uuid\t$server\t$index\t$start_call\t$end_call\t$call\t$exit_code\t$(cat $local_dump)" >> $dump_file
				else
					local time_output
					time_output=$( (time (eval "$cmd_prefix $call" > $local_dump) )2>&1 )
					local exit_code=$?
					cur_time=$(echo $time_output | cat | grep real | cut -f 2 | sed "s/.$//")
					local end_call=$(timestamp_ms)
					echo "$uuid\t$server\t$index\t$start_call\t$end_call\t$call\t$exit_code\t$cur_time" >> $output_file
					echo "$uuid\t$server\t$index\t$start_call\t$end_call\t$call\t$exit_code\t$(cat $local_dump)" >> $dump_file
				fi
				rm -f $local_dump
			} &
			pids[$counter]=$!
			counter=$((counter + 1))
			num_throttle=$((num_throttle + 1))
		done <<< "$calls"
	done
	[[ $(($(jobs -rp |wc -l))) -gt 0 ]] && echo "WAITING TO CLEAN UP PROCS" && wait

	local elapsed=$(($(timestamp) - $start))
	echo "Completed $(($counter-1)) calls in $elapsed seconds. Saved output to $output_file and dump to $dump_file."
	if [[ $open_output != 0 ]]; then
		echo "Opening output file: $output_file"
		open $output_file
	fi
}

