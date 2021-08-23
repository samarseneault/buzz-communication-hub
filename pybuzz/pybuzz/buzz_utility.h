#include <buzz/buzzneighbors.h>
#include "Python.h"

#ifndef BUZZ_UTILITY_H
#define BUZZ_UTILITY_H

#define MAX_NUM_VIRTUAL_MACHINES 15
#define MAX_MESSAGE_SIZE 1024

extern int buzz_listen(const char* type,
                       int msg_size);

extern int buzz_script_set(const char* bo_filename,
                           const char* bdbg_filename,
                           int comm_id);

extern void import_module(const char* module_name);
extern void buzz_script_destroy(void);

/*
In the following functions, vmid is the id of the buzzvm_t object,
which is the index of the buzzvm_t object in the array all_virtual_machines
*/

extern int register_hook(int vmid,
                          int hook_number,
                          const char* function_name);

extern int register_init(void);

extern void set_abs_pos(int vmid,
						float x,
						float y,
						float z);

extern void buzz_script_step(int vmid);

extern int buzz_script_done(int vmid);

extern int get_num_virtual_machines(void);

extern void reset_neighbors(int vmid);
extern void add_neighbor(int vmid, int neighbour_id, float x, float y, float z);
extern void feed_buzz_message(int vmid, int sender_id, char* message, int size);

extern int are_more_messages(int vmid);
extern char* get_next_message(int vmid);
extern int get_message_size(void);

#endif
