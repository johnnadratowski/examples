#!/usr/bin/env python
import argparse
import dateutil.parser
import dateutil.tz
import getpass
import json
import logging
import os.path
import re
import requests
import subprocess
import sys

log = logging.getLogger()

def get_prs(date, repo, user, password):
    """Get all PRs from the repo that were merged past or at the given date"""
    pull_requests_resp = requests.get("https://api.github.com/repos/Unified/%s/pulls?state=closed" % (repo), auth=(user, password))
    if pull_requests_resp.status_code != 200:
        log.error("An error occurred making API call to get PRs: Code: %d Message: %s", pull_requests_resp.status_code, pull_requests_resp.json())
        sys.exit(1)

    pr_data = []
    pull_requests = pull_requests_resp.json()
    for pull_request in pull_requests:
        merged_at_str = pull_request.get("merged_at")
        if not merged_at_str:
            continue
        merged_at_time = dateutil.parser.parse(merged_at_str).astimezone(dateutil.tz.tzlocal())
        if merged_at_time.date() >= dateutil.parser.parse(date).date():
            pr_data.append(pull_request)

    return pr_data


def get_tickets(date, user, password):
    """Get all tickets from commit messages that were merged into the current branch
    past the given date"""
    repo = subprocess.getoutput('basename `git rev-parse --show-toplevel`')
    prs = get_prs(date, repo, user, password)
    pr_numbers = sorted([pr["number"] for pr in prs])

    commits = [requests.get("https://api.github.com/repos/Unified/%s/pulls/%d/commits" % (repo, pr_num), auth=(user, password)) for pr_num in pr_numbers]
    output = {
        '_all_pr_data': prs,
        'tickets': set(),
        'num_commits_per_pr': {},
        'no_message': [],
        'invalid_message': []
    }
    for idx, pull_commits_resp in enumerate(commits):
        if pull_commits_resp.status_code != 200:
            log.error("An error occurred making API call to get commits: Code: %d Message: %s", pull_commits_resp.status_code, pull_commits_resp.json())
            sys.exit(1)

        pull_commits = pull_commits_resp.json()
        output['num_commits_per_pr'][pr_numbers[idx]] = len(pull_commits)
        for commit in pull_commits:
            try:
                commit_data = commit.get('commit', {})
                commit_msg = commit_data.get('message')
                if not commit_msg:
                    output['no_message'].append(commit)
                    continue

                ticket_matches = re.findall(r"\b([A-Z]{2,5}\-[0-9]{1,5})\b", commit_msg)
                if not ticket_matches:
                    output['invalid_message'].append(commit)
                    continue

                output['tickets'].update(ticket_matches)
            except:
                log.exception("An error occurred processing commit: %s", json.dumps(commit, sort_keys=True, indent=4, separators=(',', ': ')))
                sys.exit(1)

    pr_output = {}
    for idx, pr in enumerate(pr_numbers):
        pr_output[pr] = commits[idx].json()

    output['_prs_and_commits'] = pr_output

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
            log.warning("Getting every commit since tag %s date: %s", args.tag, date)
    else:
        date = args.date
        log.warning("Getting every commit since date: %s", date)

    if not args.user:
        log.error("Must specify a git user")
        sys.exit(1)

    log.warning("%s - make sure this is the right branch you want to run from!", subprocess.getoutput('git rev-parse --abbrev-ref HEAD'))

    if not args.password:
        password = getpass.getpass("Enter github password for user %s: " % args.user)
    else:
        password = args.password

    output = get_tickets(date, args.user, password)

    output['tickets'] = sorted(list(output['tickets']))
    print(json.dumps(output, sort_keys=True, indent=4, separators=(',', ': ')))

    sys.exit(0)
