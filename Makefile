# Makefile for Ajapopaja Plugin
VENV_DIR = .venv
PYTHON = $(VENV_DIR)/bin/python3
PIP = $(VENV_DIR)/bin/pip

.PHONY: install update clean

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

test:
	nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/lua { minimal_init = './tests/init.lua'}"

test_formatted:
	nvim --headless -u tests/init.lua -c "PlenaryBustedDirectory tests/lua { minimal_init = './tests/init.lua'}" | python3 tests/parse_test_output.py

clean:
	rm -rf $(VENV_DIR)
