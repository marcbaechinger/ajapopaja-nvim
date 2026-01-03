test:
	nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/lua { minimal_init = './tests/init.lua'}"

test_formatted:
	nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/lua { minimal_init = './tests/init.lua'}" | python tests/parse_test_output.py

