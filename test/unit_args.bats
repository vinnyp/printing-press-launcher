#!/usr/bin/env bats

load 'helpers/common.bash'

setup() {
  sb_setup_env
  sb_source
}

@test "positional only -> claude, not fresh" {
  parse_args numista
  [ "$g_name" = "numista" ]
  [ "$g_agent" = "claude" ]
  [ "$g_fresh" -eq 0 ]
}

@test "--agent agy numista" {
  parse_args --agent agy numista
  [ "$g_name" = "numista" ]
  [ "$g_agent" = "agy" ]
}

@test "--agent=agy numista" {
  parse_args --agent=agy numista
  [ "$g_agent" = "agy" ]
}

@test "--fresh sets the flag" {
  parse_args --fresh numista
  [ "$g_fresh" -eq 1 ]
}

@test "flags after positional: numista --agent agy --fresh" {
  parse_args numista --agent agy --fresh
  [ "$g_name" = "numista" ]
  [ "$g_agent" = "agy" ]
  [ "$g_fresh" -eq 1 ]
}

@test "name that looks like a former mode is just a name" {
  parse_args plan
  [ "$g_name" = "plan" ]
  [ "$g_agent" = "claude" ]
}

@test "--agent bogus -> exit 2" {
  run parse_args --agent bogus numista
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown agent 'bogus'"* ]]
}

@test "--agent with no value -> exit 2" {
  run parse_args --agent
  [ "$status" -eq 2 ]
}

@test "no positional -> usage exit 2" {
  run parse_args
  [ "$status" -eq 2 ]
}

@test "unknown flag -> usage exit 2" {
  run parse_args --bogus numista
  [ "$status" -eq 2 ]
}

@test "too many positionals -> exit 2" {
  run parse_args a b
  [ "$status" -eq 2 ]
}

@test "-h prints usage to stdout, exit 0" {
  run parse_args -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: sb"* ]]
}
