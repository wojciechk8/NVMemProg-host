# The name for the project
TARGET:=NVMemProg

# The source files of the project
SRC:=nvmemprog-application.vala nvmemprog-device.vala dbmanager.vala
SRC+= memory-device.vala memory-device-editor.vala memory-action.vala
SRC+= parser-ihex.vala

# C include directories
INCDIR:=../firmware


# Vala packages
VALAC_PKGS:=nvmemprog gtk+-3.0 gio-2.0 posix sqlite3 libusb-1.0 gtkhex-3

# Vala flags
VALAC_FLAGS:=-X -w -X -lm -g --target-glib 2.44 --save-temps


# Targets
.PHONY: all
all: $(TARGET)

.PHONY: clean
clean:
	$(RM) $(TARGET) $(SRC:%.vala=%.c)

# explicit rules
$(TARGET): $(SRC) nvmemprog.vapi libusb-1.0.vapi gtkhex-3.vapi
	valac --vapidir=. $(addprefix -X -I,$(INCDIR)) $(addprefix --pkg ,$(VALAC_PKGS)) $(VALAC_FLAGS) $(SRC) -o $@
