# Makefile for Ajapopaja Plugin
VENV_DIR = .venv
PYTHON = $(VENV_DIR)/bin/python3
PIP = $(VENV_DIR)/bin/pip

.PHONY: install update test clean

install: $(VENV_DIR)/bin/activate

$(VENV_DIR)/bin/activate: requirements.txt
	@echo "Creating virtual environment..."
	python3 -m venv $(VENV_DIR)
	@echo "Installing dependencies..."
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt
	@echo "Setup complete. Please set vim.g.python3_host_prog to $(shell pwd)/$(PYTHON)"

update: install
	$(PIP) install -r requirements.txt

test: test_lua_formatted test_python

test_lua:
	nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/lua { minimal_init = './tests/init.lua'}"

test_lua_formatted:
	nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/lua { minimal_init = './tests/init.lua'}" | python3 tests/parse_test_output.py

test_python:
	.venv/bin/pytest

clean:
	rm -rf $(VENV_DIR)
