
#include <stdlib.h>
#include <lua.h>

/*
Stack structure should be:
- pcall hook
- function to run
- arguments
*/
static inline void runLua(lua_State* L)
{
	if(L == NULL)
		abort();
	int nargs = lua_gettop(L) - 2;
	int r = lua_pcall(L, nargs, 0, 1);
	lua_pushinteger(L, r);
}

int luajitthreads_win(void* ud)
{
	runLua((lua_State*)ud);
	return 0;
}

void* luajitthreads_pthreads(void* ud)
{
	runLua((lua_State*)ud);
	return NULL;
}
