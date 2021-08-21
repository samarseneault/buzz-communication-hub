import sys
from threading import Lock
import time

sys.path.append("../OptiTrackPython")
from OptiTrackPython import NatNetClient


MIN_DISTANCE = 0.1

pose_dict = {}
robots_receiving = set()
rigidbody_names2track = {"1"}
lock_opti = Lock()

# Initialize pose_dict with initial positions
pose_dict[1] = (0.313651978969574, -0.7416703104972839, 0.016489388421177864)

# This is a callback function that gets connected to the NatNet client. It is called once per rigid body per frame
def receiveRigidBodyFrame(timestamp, id, position, rotation, rigidBodyDescriptor):
    if rigidBodyDescriptor:
        for rbname in rigidbody_names2track:
            if rbname in rigidBodyDescriptor and id == rigidBodyDescriptor[rbname][0]:
                # skips this message if still locked
                if lock_opti.acquire(False):
                    try:
                        # rotation is a quaternion!
                        pose_dict[rbname] = [timestamp, position, rotation]
                    finally:
                        lock_opti.release()

# This will create a new NatNet client
streamingClient = NatNetClient(client_ip='192.168.2.15')
streamingClient.rigidBodyListener = receiveRigidBodyFrame

# Start up the streaming client now that the callbacks are set up.
# This will run perpetually, and operate on a separate thread.
streamingClient.run()

while True:
    try:
        for key in pose_dict:
            print(f"{pose_dict[key][0]} Received frame for rigid body {key} , hex {hex(int(key)).lstrip('0x').rstrip('L')}:\n position: {pose_dict[key][1]}  orientation {pose_dict[key][2]}\n")
        time.sleep(0.01)
    except KeyboardInterrupt:
        streamingClient.is_alive = False
        break
