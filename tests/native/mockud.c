/* 测试辅助：创建带元表的 userdata，模拟 REFramework 的 sol 容器（get_elements 返回值） */
#include "lua.h"
#include "lauxlib.h"
static int mockud_new(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);          /* metatable */
  lua_newuserdatauv(L, 1, 0);
  lua_pushvalue(L, 1);
  lua_setmetatable(L, -2);
  return 1;
}
int luaopen_mockud(lua_State *L) {
  lua_newtable(L);
  lua_pushcfunction(L, mockud_new);
  lua_setfield(L, -2, "new");
  return 1;
}
