#include <stdio.h>
#include <assert.h>

#include "picrin.h"
#include "picrin/pair.h"
#include "picrin/proc.h"
#include "xhash/xhash.h"

#define FALLTHROUGH ((void)0)

struct syntactic_env {
  struct syntactic_env *up;

  struct xhash *tbl;
};

static void
define_macro(pic_state *pic, const char *name, struct pic_proc *macro)
{
  int idx;

  idx = pic->mlen++;
  pic->macros[idx] = macro;
  xh_put(pic->global_tbl, name, ~idx);
}

static struct pic_proc *
lookup_macro(pic_state *pic, struct syntactic_env *env, const char *name)
{
  struct xh_entry *e;

  e = xh_get(env->tbl, name);
  if (! e)
    return NULL;

  if (e->val >= 0)
    return NULL;

  return pic->macros[~e->val];
}

pic_value
expand(pic_state *pic, pic_value obj, struct syntactic_env *env)
{
  int ai = pic_gc_arena_preserve(pic);

  switch (pic_type(obj)) {
  case PIC_TT_SYMBOL: {
    return obj;
  }
  case PIC_TT_PAIR: {
    pic_value v;

    if (! pic_list_p(pic, obj))
      return obj;

    if (pic_symbol_p(pic_car(pic, obj))) {
      struct pic_proc *macro;
      pic_sym sym;

      sym = pic_sym(pic_car(pic, obj));
      if (sym == pic->sDEFINE_MACRO) {
	v = pic_apply(pic, pic_codegen(pic, pic_car(pic, pic_cdr(pic, pic_cdr(pic, obj)))), pic_nil_value());
	assert(pic_proc_p(v));
	define_macro(pic, pic_symbol_name(pic, pic_sym(pic_car(pic, pic_cdr(pic, obj)))), pic_proc_ptr(v));
	return pic_false_value();
      }
      macro = lookup_macro(pic, env, pic_symbol_name(pic, sym));
      if (macro) {
	v = pic_apply(pic, macro, pic_cdr(pic, obj));
	if (pic->errmsg) {
	  printf("macroexpand error: %s\n", pic->errmsg);
	  abort();
	}
	return v;
      }
    }

    v = pic_cons(pic, pic_car(pic, obj), pic_nil_value());
    for (obj = pic_cdr(pic, obj); ! pic_nil_p(obj); obj = pic_cdr(pic, obj)) {
      v = pic_cons(pic, expand(pic, pic_car(pic, obj), env), v);
    }
    v = pic_reverse(pic, v);

    pic_gc_arena_restore(pic, ai);
    pic_gc_protect(pic, v);
    return v;
  }
  case PIC_TT_NIL:
  case PIC_TT_BOOL:
  case PIC_TT_FLOAT:
  case PIC_TT_INT:
  case PIC_TT_EOF:
  case PIC_TT_STRING:
  case PIC_TT_VECTOR: {
    return obj;
  }
  case PIC_TT_PROC:
  case PIC_TT_PORT:
  case PIC_TT_ENV:
  case PIC_TT_UNDEF:
    pic_error(pic, "logic flaw");
    abort();			/* unreachable */
  }
}

pic_value
pic_expand(pic_state *pic, pic_value obj)
{
  struct syntactic_env env;
  pic_value v;
  int ai = pic_gc_arena_preserve(pic);

  env.tbl = pic->global_tbl;

  v = expand(pic, obj, &env);

  pic_gc_arena_restore(pic, ai);
  pic_gc_protect(pic, v);

#if DEBUG
  puts("expanded:");
  pic_debug(pic, v);
#endif

  return v;
}