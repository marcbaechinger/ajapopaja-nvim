test:
	nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/lua { minimal_init = './tests/init.lua'}"

