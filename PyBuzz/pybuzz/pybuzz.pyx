'''
The following code follows PEP 8 convention https://www.python.org/dev/peps/pep-0008/

Ryan Cotsakis - MIST Lab
ryan.cotsakis@polymtl.ca

This file defines the python objects available in the module "pybuzz" Which can be imported to any python script.
The objects available in the pybuzz module extend only to the classes and functions defined in this file.
The python functions that are callable in buzz execute after each step through the buzz script.
All attributes defined in each class are private, and are not intended for use outside of this file.

See example.py for an example usage on a single computer.
example_server.py and two instances of example_client.py illustrate distributed compatibility.
'''

from threading import Thread, Lock
import socket
import struct
import time
import numpy as np
import sys

# Imported from buzz_utility.h and can be used in this file. Name must be identical to the
# one in the header file.
cdef extern from "buzz_utility.h":
    cdef int buzz_script_set(const char* bo_filename, const char* bdbg_filename, int comm_id)
    cdef void import_module(const char* module_name)
    cdef int register_hook(int vmid, int hook_number, const char* function_name)
    cdef int register_init()
    cdef void complete_setup(int vmid, const char* bo_filename)
    cdef void buzz_script_step(int vmid)
    cdef void buzz_script_destroy()
    cdef int buzz_script_done(int vmid)

    cdef const int MAX_MESSAGE_SIZE

    cdef int get_num_virtual_machines()

    cdef void reset_neighbors(int vmid)
    cdef void add_neighbor(int vmid, int neighbour_id, float x, float y, float z)
    cdef void feed_buzz_message(int vmid, int sender_id, char* message, int size)
    cdef void set_abs_pos(int vmid, float x, float y, float z)

    cdef int are_more_messages(int vmid)
    cdef char* get_next_message(int vmid)
    cdef int get_message_size()

# These are python objects (only used in this file) that have been type declared to accept the return value of an array
cdef char message[MAX_MESSAGE_SIZE]

# Default host / port
HOST = 'localhost'
PORT = 8000


class Packet:
    '''
    PRIVATE
    Create a Packet to be sent over a socket
    :params x, y, z: absolute coordinates of sender
    :param sender_id: comm_id of sender
    :param msgs: list of bytes objects. Each bytes object is fed directly to the buzz script using feed_buzz_message
    '''
    def __init__(self, x, y, z, sender_id, msgs=[]):
        self.x = x
        self.y = y
        self.z = z
        self.comm_id = sender_id
        self.msgs = msgs

    '''
    PRIVATE
    Convert packet to a bytes object containing all the information.

    Contents:
        4 bytes x
        4 bytes y
        4 bytes z
        4 bytes comm_id
        for each message {
            4 bytes message length (n)
            n bytes message
        }
        4 bytes (0000)

    :return b_string: bytes object representing entire packet
    '''
    def byte_string(self):
        b_string = struct.pack('fffI', float(self.x), float(self.y), float(self.z), int(self.comm_id))
        for msg in self.msgs:
            b_string += struct.pack('I', len(msg))
            b_string += msg
        b_string += struct.pack('I', 0)
        return b_string

    '''
    PRIVATE
    Create a packet from a socket
    Block until a string of bytes comes in, and unpack these bytes into a new Packet object.
    The incomming bytes are in the form described in the documentation for Packet.byte_string
    :param s: socket object
    :return: Packet object or False if any socket.error occured
    '''
    @staticmethod
    def from_socket(s):
        try:
            while True:
                try:
                    m = s.recv(16)
                    break
                except socket.timeout:
                    pass
            if len(m) == 0:
                # The socket is broken
                return False
            # Process the message
            x, y, z, sender_id = struct.unpack('fffI', m)
            msgs = []
            while True:
                m = s.recv(4)
                msg_size = struct.unpack('I', m)[0]
                if msg_size == 0:
                    break
                msg = s.recv(msg_size)
                msgs.append(msg)
            return Packet(x, y, z, sender_id, msgs)
        except socket.error:
            return False


class BuzzVM:
    MAX_PACKETS_RECEIVED = 1000  # Receiving this many packets before stepping causes an error
    STEP_POLL_PERIOD = 0.005
    NEIGHBOR_PATIENCE = 0.5  # seconds until neighbors are forgotten
    instances = []  # List of all BuzzVM instances. Used to close their sockets in BuzzVM.destroy
    destroyed = False  # True iff destroy() was called
    hooks = {}
    py_initted = False

    '''
    Create a Buzz Virtual Machine.
    Ensure that a CommHub object has been constructed before constructing a BuzzVM object
    :param bo_filename: string. *.bo filename from compiled buzz script
    :param bdbg_filename: string. *.bdb filename from compiled buzz script
    :param robot_id: int. Id in sent packets, and the id to be assigned in the buzz script.
        If left None, automatically assign an ID unique to the other BuzzVM objects constructed from
        this script
    :param host: string. The host of the CommHub. HOST default is "localhost"
    :param port: int. The port of the CommHub. PORT default is 8000
    '''
    def __init__(self, bo_filename, bdbg_filename, robot_id=None, host=HOST, port=PORT):
        self.alive = True
        if BuzzVM.destroyed:
            raise Exception("BuzzVM: Cannot create BuzzVM object after calling BuzzVM.destroy()")
        BuzzVM.instances.append(self)  # Keep a record of this instance to close it properly
        self.id = get_num_virtual_machines()
        if robot_id is None:
            self.comm_id = self.id
        else:
            self.comm_id = robot_id

        if buzz_script_set(bo_filename.encode(), bdbg_filename.encode(), int(self.comm_id)):
            raise Exception('ERROR initializing buzz script')

        self.loc = None  # unused. Need to send this to the robot outside the buzz script.
        self.all_neighbors = {}
        self.stepping = 0  # 0: ready to step, 1: stepping, 2: step() is blocked
        self.stepping_lock = Lock()
        self.packets = []
        self.packets_lock = Lock()
        self.packets_received = 0  # Reset at every step
        self.s = None

        i = 0
        for module, hooks in BuzzVM.hooks.items():
            import_module(module.encode())
            for hook in hooks:
                if hook == "pyinit" and not BuzzVM.py_initted:
                    BuzzVM.py_initted = True
                    register_init()
                elif hook != "pyinit":
                    register_hook(self.id, i, hook.encode())
                    i += 1

        t = Thread(target=self.receive, args=(host, port), name="Receiver. BuzzVM {}".format(self.comm_id))
        t.start()

        t = Thread(target=self.stepper, name="Stepper. BuzzVM {}".format(self.comm_id))
        t.start()

        time.sleep(0.25)  # Server issues if this is not here

    '''
    PRIVATE
    New thread that blocks until new packet comes. Packets are added to self.packets 
    '''
    def receive(self, host, port):
        self.s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            self.s.connect((host, port))
        except socket.error:
            print("BuzzVM: No CommHub found during during initialization. Calling BuzzVM.destroy()")
            BuzzVM.destroy()
            return
        self.s.sendall(struct.pack('I', self.comm_id))
        while self.alive:
            p = Packet.from_socket(self.s)
            if p:
                self.packets_received += 1
                if self.packets_received > BuzzVM.MAX_PACKETS_RECEIVED:
                    print("BuzzVM: Too long since Robot {} took a step. Closing connection to server".format(self.comm_id))
                    break
                if p.comm_id == self.comm_id:
                    self.loc = (p.x, p.y, p.z)
                else:
                    # if len(p.msgs):  # Debug
                    #     print("Robot {} received a message from Robot {}".format(self.comm_id, p.comm_id))
                    self.packets_lock.acquire()
                    self.packets.append(p)
                    self.packets_lock.release()
            else:
                break
        self.s.close()
        self.loc = (0, 0, 0)  # In case we were waiting for this at the beginning of step(). Let some error be thrown
        print("BuzzVM: Robot {} lost connection to server".format(self.comm_id))

    '''
    PRIVATE
    New thread to actually do the stepping while the main thread moves onto stepping for other robots.
    '''
    def stepper(self):
        while self.alive:
            if self.stepping:  # Step
                buzz_script_step(self.id)

                # Send messages from step to neighbouring robots
                msgs = []
                while are_more_messages(self.id):
                    message = get_next_message(self.id)
                    msg_size = get_message_size()
                    msgs.append(bytes(message[:msg_size]))
                self.s.sendall(Packet(self.loc[0], self.loc[1], self.loc[2], self.comm_id, msgs).byte_string())

                self.stepping_lock.acquire()
                self.stepping -= 1
                self.stepping_lock.release()
            else:  # wait a little until next check
                time.sleep(BuzzVM.STEP_POLL_PERIOD)


    '''
    Take one step through the buzz script.
    Blocks until this robot has received its absolute position from the CommHub.
    Possible for this function to finish executing before the Buzz script step is complete.
    '''
    def step(self):
        if self.loc is None:
            print("BuzzVM: Waiting for absolute position of Robot {} before stepping...".format(self.comm_id))
            while self.loc is None:
                time.sleep(BuzzVM.STEP_POLL_PERIOD)
            print("BuzzVM: Got Robot {}'s position. Stepping...".format(self.comm_id))
        if BuzzVM.destroyed:
            raise socket.error
        # Copy list of packets and empty list self.packets
        self.packets_received = 0
        self.packets_lock.acquire()
        packets = list(self.packets)[::-1]  # Reverse the list. Most recent first
        self.packets = []
        self.packets_lock.release()

        # Update neighbor information
        reset_neighbors(self.id)
        neighbors = []
        for p in packets:
            if p.comm_id not in neighbors:
                # Robot Faces in the positive x direction
                rel_vector = np.array((p.x, p.y, p.z)) - np.array(self.loc)
                distance = np.linalg.norm(rel_vector)  # This is also computed before sending the packet
                if rel_vector[0] == 0:
                    azimuth = -90*np.sign(rel_vector[1])
                else:
                    azimuth = np.arctan2(-rel_vector[1], rel_vector[0])*180/np.pi
                elevation = np.arctan2(rel_vector[2], np.linalg.norm(rel_vector[:2]))*180/np.pi
                # Seems okay to add the same neighbor twice (potentially)
                add_neighbor(self.id, p.comm_id, float(distance), float(azimuth), float(elevation))
                self.all_neighbors[p.comm_id] = [float(distance), float(azimuth), float(elevation), time.time()]
                neighbors.append(p.comm_id)
            for msg in p.msgs:
                feed_buzz_message(self.id, p.comm_id, msg, len(msg))
        # Add neighbours that have not yet sent packets
        for i, n in self.all_neighbors.items():
            if (i not in neighbors) and (time.time() - n[3] < BuzzVM.NEIGHBOR_PATIENCE):
                add_neighbor(self.id, i, n[0], n[1], n[2])

        # Send the absolute position of the robot to the buzz script
        set_abs_pos(self.id, self.loc[0], self.loc[1], self.loc[2])

        # Step trhough buzz script TODO
        if self.stepping:  
            self.stepping_lock.acquire()
            self.stepping += 1
            self.stepping_lock.release()
            while self.stepping == 2:
                time.sleep(BuzzVM.STEP_POLL_PERIOD)
        else:
            self.stepping = 1  # signify to stepper that it's time to step. Don't need lock because it wont be decremented in stepper()

    '''
    :return: boolean. True if buzz script finished
    '''
    def is_done(self):
        return bool(buzz_script_done(self.id))

    '''
    Destroy all Virtual Machines. Do not attempt to call methods from any existing BuzzVM
    objects, or create any new ones. Also closes sockets
    '''
    @staticmethod
    def destroy():
        if len(BuzzVM.instances) and not BuzzVM.destroyed:
            BuzzVM.destroyed = True
            for bvm in BuzzVM.instances:
                while bvm.stepping:
                    time.sleep(BuzzVM.STEP_POLL_PERIOD)
                bvm.alive = False
                bvm.s.close()
            buzz_script_destroy()


class Client:
    '''
    PRIVATE
    Used by the CommHub to communicate with one of the BuzzVM objects on the client's computer.
    :param conn: socket that is used for communication with the client
    '''
    def __init__(self, conn):
        self.is_alive = True
        self.comm_id = None
        self.conn = conn
        self.packets = []
        self.packets_lock = Lock()
        self.loc = None

        self.t = Thread(target=self.receive, name="Receiver. Client {}".format(self.comm_id))
        self.t.start()

    '''
    PRIVATE
    New thread that blocks until new packet comes. Packets are added to self.packets 
    '''
    def receive(self):
        while True:
            if not self.is_alive:
                return
            try:
                m = self.conn.recv(4)
                break
            except socket.timeout:
                pass
        if len(m) == 0:
            # The socket is broken
            return False
        self.comm_id = struct.unpack('I', m)[0]
        while True:
            p = Packet.from_socket(self.conn)
            if p:
                # print("Received packet from Robot {}".format(self.comm_id))  # Debug
                self.packets_lock.acquire()
                self.packets.append(p)
                self.packets_lock.release()
            else:
                break

    '''
    PRIVATE
    Destroy this client object by stopping its receive thread and clossing its socket
    '''
    def destroy(self):
        self.is_alive = False
        self.conn.close()


class CommHub:
    TIMEOUT = 1

    '''
    Communication Hub
    Facilitate communication between the robots, as well as update their absolute positions
    :param n_clients: int. Exact number of BuzzVM objects that will connect to this CommHub
    :param forward_freq: float. Frequency of automatic calls to CommHub.forward_packets in Hertz
        Set forward_freq=0 for maximum frequency
        If left as None, CommHub.forward_packets must be called manually
    :param neighbor_distance: float. The range for communication between robots. Distance units must
        be consistent with the units used for CommHub.update_position
    :param host: string. The host of the CommHub. HOST default is "localhost"
    :param port: int. The port of the CommHub. PORT default is 8000
    '''
    def __init__(self, n_clients, forward_freq=None, neighbor_distance=1, host=HOST, port=PORT):
        self.alive = True
        self.clients_connected = False
        self.clients = {}  # comm_id : Client
        self.locs = {}  # comm_id : np.array()
        self.s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            self.s.bind((host, port))
        except OSError as e:
            print("ERROR: Trying to create a CommHub on a busy address")
            raise e
        self.s.listen(n_clients)
        self.neighbor_distance = neighbor_distance
        
        t = Thread(target=self.connect_clients, args=(n_clients,), name="Acceptor. CommHub")
        t.start()

        if forward_freq is not None:
            if forward_freq:
                period = 1/forward_freq
            else:
                period = 0
            t = Thread(target=self.auto_forward, args=(period,), name="Auto Forwarder")
            t.start()

    '''
    PRIVATE
    New blocking thread that accepts clients created during construction of BuzzVM
    :param n_clients: int. number of clients expected
    '''
    def connect_clients(self, n_clients):
        for i in range(n_clients):
            if n_clients - i == 1:
                clients = "client"
            else:
                clients = "clients"
            print("CommHub: Waiting for {} {} before forwarding packets...".format(n_clients-i, clients))
            conn, addr = self.s.accept()
            conn.settimeout(CommHub.TIMEOUT)
            c = Client(conn)
            while c.comm_id is None:
                time.sleep(0.05)
            self.clients[c.comm_id] = c
            print("CommHub: Client {} connected on {}".format(c.comm_id, addr))
        print("CommHub: All clients connected! call update_position for each robot before forwarding packets")
        self.clients_connected = True

    '''
    PRIVATE
    Send packets to a destination
    :param destination: the id of the robot to send the packages to
    :param packets: a list of Packet objects, or just a single Packet
    '''
    def send_to(self, destination, packets):
        try:
            packets[0]
        except (AttributeError, TypeError):
            self.clients[destination].conn.sendall(packets.byte_string())
            return
        m = bytes()
        for p in packets:
            m += p.byte_string()
        self.clients[destination].conn.sendall(m)

    '''
    PRIVATE
    Automatically call CommHub.forward_packets at a certain frequency
    :param period: float. Time between calls to CommHub.forward_packets in seconds
    '''
    def auto_forward(self, period):
        while (not self.clients_connected) and self.alive:
            time.sleep(0.05)
        print("CommHub: Automatically facilitating information transfer")
        while self.alive:
            self.forward_packets()
            time.sleep(period)

    '''
    Keep the communication flowing between robots.
    All information shared between robots, and any updates to positions are not sent unless this function is called.
    '''
    def forward_packets(self):
        if (not self.clients_connected) or (len(self.clients) != len(self.locs)):
            return
        found_someone_listening = False
        for i1, c1 in self.clients.items():
            if not c1.is_alive:
                continue
            c1.packets_lock.acquire()
            packets = list(c1.packets)
            c1.packets = []
            c1.packets_lock.release()
            if len(packets) == 0:
                packets = Packet(self.locs[i1][0], self.locs[i1][1], self.locs[i1][2], i1)
            for i2, c2 in self.clients.items():
                if not c2.is_alive:
                    continue
                try:
                    if i1 == i2:
                        self.send_to(i2, Packet(self.locs[i1][0], self.locs[i1][1], self.locs[i1][2], i1))
                    elif np.linalg.norm(self.locs[i2] - self.locs[i1]) < self.neighbor_distance:
                        self.send_to(i2, packets)
                    found_someone_listening = True
                except socket.error as e:
                    print("CommHub: Error sending packets to Robot {}".format(i2))
                    c2.destroy()
        if not found_someone_listening:
            self.destroy()

    '''
    Update the position of the specified robot.
    :param robot_id: int. the id of the robot whose position is to be updated
    :param loc: list, tuple, or numpy.array. The updated position of the robot
    :return: bool. True if update was successful
    '''
    def update_position(self, robot_id, loc):
        if not self.alive:
            print("CommHub: Warning: Cannot update Robot {}'s position. Communication Hub died".format(robot_id))
            return False
        if not self.clients_connected:
            print("CommHub: Waiting for clients before updating position of Robot {}".format(robot_id))
            while (not self.clients_connected) and self.alive:
                time.sleep(0.05)
        try:
            self.clients[robot_id]
            self.locs[robot_id] = np.array(loc)
            return True
        except KeyError:
            print("CommHub: Error: Cannot update Robot {}'s position. Not connected to Communication Hub".format(robot_id))
            self.destroy()
            return False

    '''
    Determine if the CommHub is still alive
    '''
    def is_alive(self):
        return self.alive

    '''
    Destroy the Communication Hub, and all its clients
    Called when CommHub.forward_packets encounters an error
    '''
    def destroy(self):
        if self.alive:  # Must check here because might have been closed automatically in CommHub.auto_forward
            self.alive = False
            for i, c in self.clients.items():
                if c.is_alive:
                    c.destroy()
            self.s.close()


'''
Decorator for Buzz hooks. Imports the python function into Buzz.
Buzz hooks must be defined before the construction of any BuzzVM objects.
Buzz hooks can take any number of int, float, and str arguments, and return
    up to one int, float, or str object to the Buzz script.

Example usage:
    @buzzhook
    def my_func(*args): ...
In Buzz:
    foo = my_func(1, 2.0, "three")
'''
def buzzhook(hook):
    module_name = hook.__module__
    if module_name == '__main__':
        module_name = sys.argv[0].split('.')[0].split('/')[-1]
    if module_name not in BuzzVM.hooks:
        BuzzVM.hooks[module_name] = []
    if hook.__name__ not in BuzzVM.hooks[module_name]:
        BuzzVM.hooks[module_name].append(hook.__name__)
        print("From '{}' import '{}' to Buzz".format(module_name, hook.__name__))
    def func(*args):
        new_args = ()
        for arg in args:
            if isinstance(arg, bytes):
                new_args += (arg.decode('utf-8'),)
            else:
                new_args += (arg,)
        ret_val = hook(*new_args)
        if isinstance(ret_val, str):
            return ret_val.encode()
        return ret_val
    return func
