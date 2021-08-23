## PyBuzz
Original repository at https://git.mistlab.ca/ryan/PyBuzz

For interacting with the Buzz Virtual Machine through Python

### Dependencies

- [Cython](http://cython.readthedocs.io/en/latest/src/quickstart/install.html)
- [Numpy](https://www.scipy.org/install.html)
- [Buzz](https://github.com/MISTLab/Buzz)

### Install 

`python setup.py build_ext --inplace`

### Usage

With `import pybuzz` one has access to the following classes and methods

``` python
class CommHub:
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
    def __init__(self, n_clients,
                       forward_freq=None,
                       neighbor_distance=1,
                       host=HOST,
                       port=PORT): ...

    '''
    Keep the communication flowing between robots.
    All information shared between robots, and any updates to positions are not sent unless
    this function is called.
    '''
    def forward_packets(self): ...

    '''
    Update the position of the specified robot.
    :param robot_id: int. the id of the robot whose position is to be updated
    :param loc: list, tuple, or numpy.array. The new position of the robot
    :return: bool. True if update was successful
    '''
    def update_position(self, robot_id, loc): ...

    '''
    Determine if the CommHub is still alive. 
    '''
    def is_alive(self): ...

    '''
    Destroy the Communication Hub, and all its clients
    Called when CommHub.forward_packets encounters an error
    '''
    def destroy(self): ...


class BuzzVM:
    '''
    Create a Buzz Virtual Machine.
    Ensure that a CommHub object has been constructed before constructing a BuzzVM object
    :param bo_filename: string. *.bo filename from compiled buzz script
    :param bdbg_filename: string. *.bdb filename from compiled buzz script
    :param robot_id: int. Id in sent packets, and the id to be assigned in the buzz script.
        If left None, automatically assign an ID unique to the other BuzzVM objects
        constructed from this script
    :param host: string. The host of the CommHub. HOST default is "localhost"
    :param port: int. The port of the CommHub. PORT default is 8000
    '''
    def __init__(self, bo_filename,
                       bdbg_filename,
                       robot_id=None,
                       host=HOST,
                       port=PORT): ...

	'''
    Take one step through the buzz script.
    Blocks until this robot has received its absolute position from the CommHub.
    Possible for this function to finish executing before the Buzz script step is complete.
    '''
    def step(self): ...

    '''
    :return: boolean. True if buzz script finished
    '''
    def is_done(self): ...

    '''
    Destroy all Virtual Machines. Do not attempt to call methods from any existing BuzzVM
    objects, or create any new ones. Also closes sockets
    '''
    @staticmethod
    def destroy(): ...
```

Use the `pybuzz` decorator `@buzzhook` to make a Python function a Buzz hook. This will automatically import the function into Buzz. The function can take any number of str, int, and float arguments, and can return an int, float, or str object to the Buzz script. **Do not delare a buzzhook in a file with a global BuzzVM or CommHub**

When `pybuzz` is imported into Python, a new Python interpreter is created, and shared by the Buzz Virtual Machines to call the buzzhook functions. To initialize global variables in Python environment, create a new buzzhook called `pyinit()`, in which global variables can be declared and used in the other buzzhooks. If defined, `pyinit()` will be called once automatically during the initialization of the first BuzzVM.

Additionally, in Buzz, one has access to the Buzz table `absolute_position` which has attributes *x*, *y*, and *z*. Global Buzz variables `True` and `False` are defined as 1 and 0 respectively.

### Example

Server - *Python*:

``` python
from pybuzz import CommHub
import sys
import time

comm_hub = CommHub(2)  # Wait for 2 clients

while comm_hub.is_alive():
    comm_hub.update_position(int(sys.argv[1]), (0.1, 0.2, 0.3))
    comm_hub.update_position(int(sys.argv[2]), (0.4, 0.5, 0.6))
    comm_hub.forward_packets()
    time.sleep(0.01)
```

Client - *Python*:

``` python
from pybuzz import buzzhook, BuzzVM
import sys
import time

@buzzhook
def pyinit():
    global start_time
    start_time = time.time()

@buzzhook
def my_add(a, b):
    print("Adding {} and {} after {} seconds".format(a, b, time.time() - start_time))
    return a + b

def run():
    vm = BuzzVM("example.bo", "example.bdb", int(sys.argv[1]))

    for i in range(5):
        vm.step()
        time.sleep(1)

    BuzzVM.destroy()

if __name__ == "__main__":
    run()
```

example.bzz - *Buzz*:

``` python
function init() {
    i = 1
}

function step() {
    log("Robot ", id, " step: ", i)
    i = my_add(i, 1)

    log("Robot ", id, ": (",
        absolute_position.x, ", ",
        absolute_position.y, ", ",
        absolute_position.z, ")")
}
```


**Ryan Cotsakis - MIST Lab**

August 13 2018
