
#include <stdlib.h>
#include <lua.h>

int luajitthreads_win(void* ud)
{
	lua_State* L = (lua_State*)ud;
	if(L == NULL)
		abort();
	int r = lua_pcall(L, 0, 0, -2);
	lua_pushinteger(L, r);
	return 0;
}

void* luajitthreads_pthreads(void* ud)
{
	lua_State* L = (lua_State*)ud;
	if(L == NULL)
		abort();
	int r = lua_pcall(L, 0, 0, -2);
	lua_pushinteger(L, r);
	return NULL;
}
