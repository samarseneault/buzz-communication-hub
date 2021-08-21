import cflib.crtp
from threading import Thread, Lock
import time
import sys

sys.path.append("../OptiTrackPython")
from OptiTrackPython import from_quaternion2rpy, NatNetClient

sys.path.append("../PyBuzz")
from pybuzz import CommHub


# Initiate the low level drivers
cflib.crtp.init_drivers(enable_debug_driver=False)

# Parameters for the Buzz ComHub
FORWARD_FREQ = 50  # Hz
PORT = 8002
M_IP = '192.168.2.105'
S_IP = '192.168.2.100'
MULTICAST_ADDRESS = "239.255.42.99"

KH4IPS = {1: '192.168.2.142', 2: '192.168.2.143', 3: '192.168.2.144', 4: '192.168.2.145',
          5: '192.168.2.146', 6: '192.168.2.147', 7: '192.168.2.148', 8: '192.168.2.149',
          9: '192.168.2.150', 10: '192.168.2.151'}
KH4PORT = 24580

# For the rigid body detection
pose_dict = {}
rigidbody_names2track = {"1"}
CF_CLIENTS = {}
KH4_CLIENTS = {1}
lock_opti = Lock()

# For the comm_hub
comm_hub = None
dead = False


def kh4_com_pos_updater():
    while not dead:
        for i in KH4_CLIENTS:
            if str(i) in pose_dict:
                _, _, y = from_quaternion2rpy(pose_dict[str(i)][2])
                comm_hub.update_position(i, pose_dict[str(i)][1], y)
        time.sleep(0.01)


def start():
    global comm_hub
    comm_hub = CommHub(0, cf_clients={}, kh4_clients=KH4_CLIENTS,
                       forward_freq=FORWARD_FREQ, neighbor_distance=1.7, host=M_IP, port=PORT, kh4ips=KH4IPS, kh4port=KH4PORT)

    kh4_commpos_updater_thread = Thread(target=kh4_com_pos_updater, name="kh4_pos_updater")
    kh4_commpos_updater_thread.start()

    try:
        kh4_commpos_updater_thread.join()
    except KeyboardInterrupt:
        pass

    global dead
    dead = True
    sys.exit(0)


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


if __name__ == '__main__':
    # This will create a new NatNet client
    nnc = NatNetClient(M_IP, S_IP, MULTICAST_ADDRESS)

    # Configure the streaming client to call the rigid body handler or the markers handler

    nnc.rigidBodyListener = receiveRigidBodyFrame
    nnc.run()

    start()
