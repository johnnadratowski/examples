#!/bin/bash

callmee() (

	init() {
		foo=1
		bar=2
	}

	init

	printf "FOO: %s BAR: %s" "$foo" "$bar"
)
