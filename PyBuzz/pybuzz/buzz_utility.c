#define _GNU_SOURCE
#include <stdio.h>

#include "buzz_utility.h"
#include <buzz/buzzdebug.h>

#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <sys/types.h>

/****************************************/
/****************************************/

static char*       BO_FNAME       = 0;
static uint8_t*    BO_BUF         = 0;
static buzzdebug_t DBG_INFO       = 0;

/* For sending and receiving buzz messages */
static int message_size = 0;

/* For calling python hooks */
static int python_initialized = 0;
static int vm_stepped[MAX_NUM_VIRTUAL_MACHINES];  // initialized to all 0's (False)
static PyObject* python_funcs[20];
static PyObject* python_module = NULL;
static PyObject* init_func = NULL;

/* Buzz Virtual Machine */
static buzzvm_t all_virtual_machines[MAX_NUM_VIRTUAL_MACHINES];
static buzzvm_t vm = NULL;
static int num_virtual_machines = 0;

/****************************************/
/****************************************/

static const char* buzz_error_info(buzzvm_t vm) {
   buzzdebug_entry_t dbg = *buzzdebug_info_get_fromoffset(DBG_INFO, &vm->pc);
   char* msg;
   if(dbg != NULL) {
      asprintf(&msg,
               "%s: execution terminated abnormally at %s:%" PRIu64 ":%" PRIu64 " : %s\n\n",
               BO_FNAME,
               dbg->fname,
               dbg->line,
               dbg->col,
               vm->errormsg);
   }
   else {
      asprintf(&msg,
               "%s: execution terminated abnormally at bytecode offset %d: %s\n\n",
               BO_FNAME,
               vm->pc,
               vm->errormsg);
   }
   return msg;
}

/****************************************/
/****************************************/

int get_num_virtual_machines() {
  return num_virtual_machines;
}

/****************************************/
/****************************************/

/*
This is not a python callback. This is called during the execution of the buzz
script, before any python callbacks called during the same step.
*/
static int buzz_print(buzzvm_t vm) {
   int i;
   for(i = 1; i < buzzdarray_size(vm->lsyms->syms); ++i) {
      buzzvm_lload(vm, i);
      buzzobj_t o = buzzvm_stack_at(vm, 1);
      buzzvm_pop(vm);
      // if(i > 1) fprintf(stdout, " ");  // Arguments are separated by a space
      switch(o->o.type) {
         case BUZZTYPE_NIL:
            fprintf(stdout, "[nil]");
            break;
         case BUZZTYPE_INT:
            fprintf(stdout, "%d", o->i.value);
            break;
         case BUZZTYPE_FLOAT:
            fprintf(stdout, "%f", o->f.value);
            break;
         case BUZZTYPE_TABLE:
            fprintf(stdout, "[table with %d elems]", (buzzdict_size(o->t.value)));
            break;
         case BUZZTYPE_CLOSURE:
            if(o->c.value.isnative)
               fprintf(stdout, "[n-closure @%d]", o->c.value.ref);
            else
               fprintf(stdout, "[c-closure @%d]", o->c.value.ref);
            break;
         case BUZZTYPE_STRING:
            fprintf(stdout, "%s", o->s.value.str);
            break;
         case BUZZTYPE_USERDATA:
            fprintf(stdout, "[userdata @%p]", o->u.value);
            break;
         default:
            break;
      }
   }
   fprintf(stdout, "\n");
   return buzzvm_ret0(vm);
}

/* Takes values from the virtual machine and fills the callback arrays */
static int python_callback(buzzvm_t vm, int hook_id) {
   int i;
   int size = buzzdarray_size(vm->lsyms->syms);
   PyObject *pArgs, *pValue;

   pArgs = PyTuple_New(size-1);
   for(i = 1; i < size; ++i) {
      buzzvm_lload(vm, i);
      buzzobj_t o = buzzvm_stack_at(vm, 1);
      buzzvm_pop(vm);
      switch(o->o.type) {
         case BUZZTYPE_INT:
            PyTuple_SetItem(pArgs, i-1, PyLong_FromLong(o->i.value));
            break;
         case BUZZTYPE_FLOAT:
            PyTuple_SetItem(pArgs, i-1, PyFloat_FromDouble(o->f.value));
            break;
         case BUZZTYPE_STRING:
            PyTuple_SetItem(pArgs, i-1, PyBytes_FromString(o->s.value.str));
            break;
         default:
            PyTuple_SetItem(pArgs, i-1, Py_None);
            break;
      }
   }
   pValue = PyObject_CallObject(python_funcs[hook_id], pArgs);
   if(PyLong_Check(pValue))
      buzzvm_pushi(vm, PyLong_AsLong(pValue));

   else if(PyFloat_Check(pValue))
      buzzvm_pushf(vm, PyFloat_AsDouble(pValue));

   else if(PyBytes_Check(pValue))  // Not returning a String object from Python but a Bytes object
      buzzvm_pushs(vm, buzzvm_string_register(vm, PyBytes_AsString(pValue), 1));

   else
      buzzvm_pushnil(vm);

   return buzzvm_ret1(vm);
}

/*
The buzz functions must be registered to unique C functions that take a buzzvm_t object. 
They are defined here.
To change the number of allowable python hooks, one must also change the size of python_funcs
*/
static int h0(buzzvm_t vm) {
  return python_callback(vm, 0);
};
static int h1(buzzvm_t vm) {
  return python_callback(vm, 1);
};
static int h2(buzzvm_t vm) {
  return python_callback(vm, 2);
};
static int h3(buzzvm_t vm) {
  return python_callback(vm, 3);
};
static int h4(buzzvm_t vm) {
  return python_callback(vm, 4);
};
static int h5(buzzvm_t vm) {
  return python_callback(vm, 5);
};
static int h6(buzzvm_t vm) {
  return python_callback(vm, 6);
};
static int h7(buzzvm_t vm) {
  return python_callback(vm, 7);
};
static int h8(buzzvm_t vm) {
  return python_callback(vm, 8);
};
static int h9(buzzvm_t vm) {
  return python_callback(vm, 9);
};
static int h10(buzzvm_t vm) {
  return python_callback(vm, 10);
};
static int h11(buzzvm_t vm) {
  return python_callback(vm, 11);
};
static int h12(buzzvm_t vm) {
  return python_callback(vm, 12);
};
static int h13(buzzvm_t vm) {
  return python_callback(vm, 13);
};
static int h14(buzzvm_t vm) {
  return python_callback(vm, 14);
};
static int h15(buzzvm_t vm) {
  return python_callback(vm, 15);
};
static int h16(buzzvm_t vm) {
  return python_callback(vm, 16);
};
static int h17(buzzvm_t vm) {
  return python_callback(vm, 17);
};
static int h18(buzzvm_t vm) {
  return python_callback(vm, 18);
};
static int h19(buzzvm_t vm) {
  return python_callback(vm, 19);
};
/* The C hooks are stored in this array in the correct order, so that hooks[n](vm) == python_callback(vm, n) */
static int (*hooks[])(buzzvm_t vm) = {h0, h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, h12, h13, h14, h15, h16, h17, h18, h19};

/****************************************/
/****************************************/

/* initialize the virtual machine */
int buzz_script_set(const char* bo_filename,
                    const char* bdbg_filename,
                    int comm_id) {

   vm = buzzvm_new(comm_id);
   all_virtual_machines[num_virtual_machines] = vm;
   num_virtual_machines++;

   /* Get rid of debug info */
   if(DBG_INFO) buzzdebug_destroy(&DBG_INFO);
   DBG_INFO = buzzdebug_new();
   /* Read bytecode and fill in data structure */
   FILE* fd = fopen(bo_filename, "rb");
   if(!fd) {
      perror(bo_filename);
      return 1;
   }
   fseek(fd, 0, SEEK_END);
   size_t bcode_size = ftell(fd);
   rewind(fd);
   BO_BUF = (uint8_t*)malloc(bcode_size);
   if(fread(BO_BUF, 1, bcode_size, fd) < bcode_size) {
      perror(bo_filename);
      buzzvm_destroy(&vm);
      buzzdebug_destroy(&DBG_INFO);
      fclose(fd);
      return 1;
   }
   fclose(fd);
   /* Read debug information */
   if(!buzzdebug_fromfile(DBG_INFO, bdbg_filename)) {
      buzzvm_destroy(&vm);
      buzzdebug_destroy(&DBG_INFO);
      perror(bdbg_filename);
      return 1;
   }
   /* Set byte code */
   if(buzzvm_set_bcode(vm, BO_BUF, bcode_size) != BUZZVM_STATE_READY) {
      buzzvm_destroy(&vm);
      buzzdebug_destroy(&DBG_INFO);
      fprintf(stdout, "%s: Error loading Buzz script\n\n", bo_filename);
      return 1;
   }
   /* Register print hook */
   buzzvm_pushs(vm,  buzzvm_string_register(vm, "print", 1));
   buzzvm_pushcc(vm, buzzvm_function_register(vm, buzz_print));
   buzzvm_gstore(vm);
   buzzvm_pushs(vm,  buzzvm_string_register(vm, "log", 1));
   buzzvm_pushcc(vm, buzzvm_function_register(vm, buzz_print));
   buzzvm_gstore(vm);

   /* Register boolean identifiers */
   buzzvm_pushs(vm, buzzvm_string_register(vm, "True", 1));
   buzzvm_pushi(vm, 1);
   buzzvm_gstore(vm);
   buzzvm_pushs(vm, buzzvm_string_register(vm, "False", 1));
   buzzvm_pushi(vm, 0);
   buzzvm_gstore(vm);

   /* Start a new Python interpreter */
   if(!python_initialized) {
      Py_Initialize();
      PyRun_SimpleString("import os, sys\n"
                         "sys.path.append(os.getcwd())\n"
                         );

      python_initialized = 1;
   }

   /* Save bytecode file name */
   BO_FNAME = strdup(bo_filename);

   return 0;
}

void import_module(const char* module_name) {
  python_module = PyImport_ImportModule(module_name);
}

/*
In the list or tuple of BuzzHook objects passed to the BuzzVM during initialization in the .pyx file,
the <n>th element is registered to the C function h<n>.
*/
int register_hook(int vmid, int hook_number, const char* function_name) {
   vm = all_virtual_machines[vmid];
   python_funcs[hook_number] = PyObject_GetAttrString(python_module, function_name);
   if(!PyCallable_Check(python_funcs[hook_number])) {
     printf("ERROR: Function '%s' not defined\n", function_name);
     return 1;
   }
   buzzvm_pushs(vm,  buzzvm_string_register(vm, function_name, 1));
   buzzvm_pushcc(vm, buzzvm_function_register(vm, hooks[hook_number]));
   buzzvm_gstore(vm);
   return 0;
}

int register_init() {
  init_func = PyObject_GetAttrString(python_module, "pyinit");
  if(!PyCallable_Check(init_func)) {
     printf("ERROR: Function 'init' not defined\n");
     return 1;
  }
  PyObject_CallObject(init_func, NULL);
  return 0;
}

/****************************************/
/****************************************/

/* Used to update neighbor and message information in the buzz script before the step */

void reset_neighbors(int vmid) {
  vm = all_virtual_machines[vmid];
  buzzneighbors_reset(vm);
}

void add_neighbor(int vmid, int neighbour_id, float x, float y, float z) {
  vm = all_virtual_machines[vmid];
  buzzneighbors_add(vm, (uint16_t)neighbour_id, x, y, z);
}

void feed_buzz_message(int vmid, int sender_id, char* message, int size) {
  vm = all_virtual_machines[vmid];
  buzzinmsg_queue_append(
    vm,
    (uint16_t)sender_id,
    buzzmsg_payload_frombuffer((void*)message, size));
}

void set_abs_pos(int vmid, float x, float y, float z) {
  vm = all_virtual_machines[vmid];
  buzzvm_pushs(vm, buzzvm_string_register(vm, "absolute_position", 1));
  buzzvm_pusht(vm);
  buzzvm_dup(vm);
  buzzvm_pushs(vm, buzzvm_string_register(vm, "x", 1));
  buzzvm_pushf(vm, x);
  buzzvm_tput(vm);
  buzzvm_dup(vm);
  buzzvm_pushs(vm, buzzvm_string_register(vm, "y", 1));
  buzzvm_pushf(vm, y);
  buzzvm_tput(vm);
  buzzvm_dup(vm);
  buzzvm_pushs(vm, buzzvm_string_register(vm, "z", 1));
  buzzvm_pushf(vm, z);
  buzzvm_tput(vm);
  buzzvm_gstore(vm);
}

/* Take one step through the buzz script */
void buzz_script_step(int vmid) {
   vm = all_virtual_machines[vmid];

   if(!vm_stepped[vmid]){
     /* Execute the global part of the script */
     buzzvm_execute_script(vm);
     /* Call the Init() function */
     buzzvm_function_call(vm, "init", 0);
     vm_stepped[vmid] = 1;
   }

   /* Process packets */
   buzzvm_process_inmsgs(vm);

   /*
    * Call Buzz step() function
    */
   if(buzzvm_function_call(vm, "step", 0) != BUZZVM_STATE_READY) {
      fprintf(stderr, "%s: execution terminated abnormally: %s\n\n",
              BO_FNAME,
              buzz_error_info(vm));
      buzzvm_dump(vm);
   }
}

/* Extract the messages sent from the buzz script */

int are_more_messages(int vmid) {
  vm = all_virtual_machines[vmid];
  return !buzzoutmsg_queue_isempty(vm);
}

char* get_next_message(int vmid) {
  vm = all_virtual_machines[vmid];
  buzzmsg_payload_t m = buzzoutmsg_queue_first(vm);
  message_size = buzzmsg_payload_size(m);
  buzzoutmsg_queue_next(vm);
  return (char*)m->data;
}

int get_message_size() {
  return message_size;
}

/****************************************/
/****************************************/

/* destroy all virtual machines */
void buzz_script_destroy(void) {
   int i;
   /* Get rid of virtual machines */
   for (i = 0; i < num_virtual_machines; ++i) {
      vm = all_virtual_machines[i];
      if(vm->state != BUZZVM_STATE_READY) {
         fprintf(stderr, "%s: execution terminated abnormally: %s\n\n",
                 BO_FNAME,
                 buzz_error_info(vm));
         buzzvm_dump(vm);
      }
      buzzvm_function_call(vm, "destroy", 0);
      buzzvm_destroy(&vm);
   }
   free(BO_FNAME);
   buzzdebug_destroy(&DBG_INFO);
   num_virtual_machines = 0;  // I don't think this is necessary
   fprintf(stdout, "Script execution stopped.\n");
}

/****************************************/
/****************************************/

int buzz_script_done(int vmid) {
   return vm->state != BUZZVM_STATE_READY;
}
