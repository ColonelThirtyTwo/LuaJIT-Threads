
#include <stdlib.h>
#include <lua.h>

static inline void runLua(lua_State* L)
{
	if(L == NULL)
		abort();
	int r = lua_pcall(L, 0, 0, -2);
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
