#ifndef PORT_H__
#define PORT_H__

#include <stdio.h>

enum pic_port_flag {
  PIC_PORT_IN = 1,
  PIC_PORT_OUT = 2,
  PIC_PORT_TEXT = 4,
  PIC_PORT_BINARY = 8,
};

enum pic_port_status {
  PIC_PORT_OPEN,
  PIC_PORT_CLOSE,
};

typedef struct {
  char *buf;
  int mode;
  int bufsiz;
  struct {
    void *cookie;
    int (*read)(void *, char *, int);
    int (*write)(void *, const char *, int);
    fpos_t (*seek)(void *, fpos_t, int);
    int (*close)(void *);
  } vtable;
} pic_file;

struct pic_port {
  PIC_OBJECT_HEADER
  pic_file *file;
  int flags;
  int status;
};

#define pic_port_p(v) (pic_type(v) == PIC_TT_PORT)
#define pic_port_ptr(v) ((struct pic_port *)pic_ptr(v))

pic_value pic_eof_object();

struct pic_port *pic_stdin(pic_state *);
struct pic_port *pic_stdout(pic_state *);
struct pic_port *pic_stderr(pic_state *);

int pic_setvbuf(pic_file *, char *, int, size_t);
int pic_fflush(pic_file *);

pic_file *pic_funopen(void *cookie, int (*read)(void *, char *, int), int (*write)(void *, const char *, int), fpos_t (*seek)(void *, fpos_t, int), int (*close)(void *));

pic_file *pic_fopen(const char *, const char *);
int pic_fclose(pic_file *);

size_t pic_fread(void *, size_t, size_t, pic_file *);
size_t pic_fwrite(const void *, size_t, size_t, pic_file *);

int pic_fgetc(pic_file *);
int pic_ungetc(int, pic_file *);
int pic_fputc(int, pic_file *);
int pic_fputs(const char *, pic_file *);

#endif
