all: clean package

clean:
	rm -rf .build .test

package:
	bash package.sh

install:
	install -d $(DESTDIR)$(prefix)/usr/bin
	install -m 755 src/main/script/jrun.sh $(DESTDIR)$(prefix)/usr/bin/jrun
	bash install-binfmt.sh

test:
	bash test.sh
