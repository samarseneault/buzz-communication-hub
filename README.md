# buzz-communication-hub

This is a communication hub designed to help tracking and updating robots' positions with the OptiTrack.

## Installation
It is necessary to install PyBuzz locally. Follow these [instructions](PyBuzz/README.md).

## Usage
Make sure the OptiTrack is correctly running and tracking the desired rigidbodies,
then run these commands on your laptop (or whatever you are using as a server):

```bash
cd communication_hub
python3 commhub_server.py
```
