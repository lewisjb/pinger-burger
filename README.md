# Pinger Burger

  Solution to TandaHQ/work-samples/pings

  Contains two scripts, the netcat version doesn't work with the test scripts
  due to how it works.

## Requirements

- pinger-burger-netcat.sh
  Bash, GNU `date`, GNU `netcat`

- pinger-burger-socat.sh
  Bash, GNU `date`, `socat`

## Usage

 - pinger-burger-netcat.sh
   `./pinger-burger-netcat.sh`

- pinger-burder-socat.sh
  `socat TCP4-LISTEN:3000,fork EXEC:./pinger-burger-socat.sh`
