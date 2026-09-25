#include <stdio.h>
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lobject.h"
#include "lstate.h"
#include "ltable.h"
#include "lstring.h"
#include "lfunc.h"

static void push_key(lua_State *L, const TValue *k) {
  if (ttisstring(k)) lua_pushstring(L, getstr(rawtsvalue(k)));
  else if (ttisnumber(k)) lua_pushnumber(L, nvalue(k));
  else if (ttisboolean(k)) lua_pushboolean(L, bvalue(k));
  else if (ttisnil(k)) lua_pushboolean(L, 0);
  else if (ttype(k) == LUA_TDEADKEY) lua_pushstring(L, "<dead>");
  else lua_pushstring(L, "<non-scalar key>");
}

static const Node *dummynode_address(lua_State *L) {
  const Node *d;
  lua_newtable(L);
  d = hvalue(L->top - 1)->node;
  lua_pop(L, 1);
  return d;
}

#define dummynode dummynode_address(L)

static int layout(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  Table *t = hvalue(L->base);
  int size = sizenode(t);
  int i;
  lua_createtable(L, 0, 6);
  lua_pushinteger(L, t->sizearray);
  lua_setfield(L, -2, "sizearray");
  lua_pushinteger(L, t->lsizenode);
  lua_setfield(L, -2, "lsizenode");
  lua_pushinteger(L, t->node == dummynode ? 0 : (int)(t->lastfree - t->node));
  lua_setfield(L, -2, "lastfree");
  lua_pushboolean(L, t->node == dummynode);
  lua_setfield(L, -2, "dummy");
  lua_createtable(L, t->sizearray, 0);
  for (i = 0; i < t->sizearray; i++) {
    lua_pushboolean(L, !ttisnil(&t->array[i]));
    lua_rawseti(L, -2, i + 1);
  }
  lua_setfield(L, -2, "array");
  lua_createtable(L, size, 0);
  for (i = 0; i < size && t->node != dummynode; i++) {
    Node *n = gnode(t, i);
    lua_createtable(L, 0, 4);
    push_key(L, key2tval(n));
    lua_setfield(L, -2, "key");
    lua_pushboolean(L, !ttisnil(gval(n)));
    lua_setfield(L, -2, "live");
    lua_pushinteger(L, gnext(n) ? (int)(gnext(n) - t->node) : -1);
    lua_setfield(L, -2, "next");
    if (ttisstring(key2tval(n))) {
      lua_pushnumber(L, (lua_Number)rawtsvalue(key2tval(n))->tsv.hash);
      lua_setfield(L, -2, "hash");
    }
    lua_rawseti(L, -2, i + 1);
  }
  lua_setfield(L, -2, "nodes");
  return 1;
}

static int string_hash(lua_State *L) {
  luaL_checktype(L, 1, LUA_TSTRING);
  lua_pushnumber(L, (lua_Number)rawtsvalue(L->base)->tsv.hash);
  return 1;
}

static int proto_constants(lua_State *L) {
  Closure *cl;
  Proto *p;
  int i, n = 0;
  luaL_checktype(L, 1, LUA_TFUNCTION);
  cl = clvalue(L->base);
  lua_newtable(L);
  if (cl->c.isC) return 1;
  p = cl->l.p;
  for (i = 0; i < p->sizek; i++) {
    if (ttisnumber(&p->k[i])) {
      lua_pushnumber(L, nvalue(&p->k[i]));
      lua_rawseti(L, -2, ++n);
    }
  }
  return 1;
}

static int f64_bits(lua_State *L) {
  lua_Number x = luaL_checknumber(L, 1);
  unsigned long long bits;
  char text[17];
  memcpy(&bits, &x, sizeof bits);
  snprintf(text, sizeof text, "%016llx", bits);
  lua_pushstring(L, text);
  return 1;
}

int luaopen_tablelayout(lua_State *L) {
  lua_createtable(L, 0, 4);
  lua_pushcfunction(L, f64_bits);
  lua_setfield(L, -2, "f64_bits");
  lua_pushcfunction(L, proto_constants);
  lua_setfield(L, -2, "constants");
  lua_pushcfunction(L, layout);
  lua_setfield(L, -2, "layout");
  lua_pushcfunction(L, string_hash);
  lua_setfield(L, -2, "hash");
  return 1;
}
