FIRMWARE_DIR 		= ./firmware/build/
LOG_DIR		 		= ./

LOADER_FIRMWARE 	= $(FIRMWARE_DIR)loader.hex
LOADER_LOG 			= $(LOG_DIR)loader.log

ECHO_FIRMWARE 		= $(FIRMWARE_DIR)echo.hex
ECHO_LOG 			= $(LOG_DIR)echo.log

CYCLEMARK_FIRMWARE 	= $(FIRMWARE_DIR)cyclemark.hex
CYCLEMARK_LOG 		= $(LOG_DIR)cyclemark.log

.PHONY: loader
loader:
	./platform --firmware $(LOADER_FIRMWARE) --log $(LOADER_LOG)

.PHONY: echo
echo:
	./platform --firmware $(ECHO_FIRMWARE) --log $(ECHO_LOG)

.PHONY: cyclemark
cyclemark:
	./platform --firmware $(CYCLEMARK_FIRMWARE) --log $(CYCLEMARK_LOG)
