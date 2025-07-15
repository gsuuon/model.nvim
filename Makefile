test:
	nvim --headless --noplugin -u lua/tests/init.vim -c "PlenaryBustedDirectory lua/tests { minimal_init = './lua/tests/init.vim' }"

test-file:
	nvim --headless --noplugin -u lua/tests/init.vim -c "PlenaryBustedFile $(FILE)"
