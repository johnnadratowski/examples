#!/usr/bin/env python
import argparse
import getpass
import json
import logging
import os.path
import re
import requests
import subprocess
import sys

log = logging.getLogger()

def get_tickets(date, user, password):

    repo = subprocess.getoutput('basename `git rev-parse --show-toplevel`')
    prs = subprocess.getoutput('git log --after="{date}" --grep="Merge pull request" --format="%s"'.format(date=date))
    prs = prs.split("\n")
    prs = [re.search("\#([0-9]+)", pr).group(1) for pr in prs]

    commits = [requests.get("https://api.github.com/repos/Unified/%s/pulls/%s/commits" % (repo, pr), auth=(user, password)) for pr in prs]
    output = {
        'tickets': set(),
        'no_message': [],
        'invalid_message': []
    }
    for pull_commits in commits:
        if pull_commits.status_code != 200:
            log.error("An error occurred making API call: Code: %d Message: %s", pull_commits.status_code, pull_commits.json())
            sys.exit(1)

        for commit in pull_commits.json():
            try:
                commit_data = commit.get('commit', {})
                commit_msg = commit_data.get('message')
                if not commit_msg:
                    output['no_message'].append("No commit message: %s" % json.dumps(commit, sort_keys=True, indent=4, separators=(',', ': ')))
                    continue

                ticket_matches = re.search("^([a-zA-Z]+\-[0-9]+)", commit_msg)
                if not ticket_matches:
                    output['invalid_message'].append("Commit message invalid: %s" % json.dumps(commit, sort_keys=True, indent=4, separators=(',', ': ')))
                    continue

                output['tickets'].add(ticket_matches.group(1))
            except:
                log.exception("An error occurred processing commit: %s", json.dumps(commit, sort_keys=True, indent=4, separators=(',', ': ')))
                sys.exit(1)

    pr_output = {}
    for idx, pr in enumerate(prs):
        pr_output[pr] = commits[idx].json()

    output['prs_and_commits'] = pr_output

    return output


def get_tag_date(tag):
    tags_data = subprocess.getoutput('git log --tags --simplify-by-decoration --pretty="format:%ai %d"')
    for tag_data in tags_data.split("\n"):
        if "tag: %s" % tag in tag_data:
            return tag_data.split(" ")[0]
    log.error("Could not find tag %s", tag)
    sys.exit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="""
                                     Get all of the ticket numbers from commits in PRs made since the specified date.
                                     Must either be explicitly given a date, or given a tag and the tag date will be used.
                                     Output as JSON with tickets and error messages.""")
    parser.add_argument('--tag', '-t', dest='tag', help='Get all PRs since tag')
    parser.add_argument('--date', '-d', dest='date', help='The date to start looking for PRs - like 2016-01-28')
    parser.add_argument('--user', '-u', dest='user', help='The github api user to use')
    parser.add_argument('--password', '-p', dest='password', help='The github api password to use')
    args = parser.parse_args()

    if not os.path.isdir(os.path.abspath("./.git")):
        log.error("You must run this from a git repo root folder")
        sys.exit(1)

    is_up_to_date = subprocess.getoutput('git remote update; git status -uno')
    if 'Your branch is up-to-date' not in is_up_to_date:
        log.error("Your branch is out of date - rerun this after you pull")
        sys.exit(1)

    if not args.date:
        if not args.tag:
            log.error("Must specify either the explicit date to find PR tickets from, or a git tag that will serve as the start date.")
            sys.exit(1)
        else:
            date = get_tag_date(args.tag)
    else:
        date = args.date

    if not args.user:
        log.error("Must specify a git user")
        sys.exit(1)

    log.warning("%s - make sure this is the right branch you want to run from!", is_up_to_date.split("\n")[1])

    if not args.password:
        password = getpass.getpass("Enter github password for user %s: " % args.user)
    else:
        password = args.password

    output = get_tickets(date, args.user, password)

    output['tickets'] = list(output['tickets'])
    print(json.dumps(output, sort_keys=True, indent=4, separators=(',', ': ')))

    sys.exit(0)
