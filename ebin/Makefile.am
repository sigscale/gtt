## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

appdir = $(beamdir)
app_DATA = gtt.app
EXTRA_DIST = gtt.app

beam_DATA = gtt.beam \
		gtt_app.beam \
		gtt_sup.beam \
		gtt_server.beam

%.beam:$(top_srcdir)/src/%.erl
	$(ERLC) $(ERLCFLAGS) -I $(top_srcdir)/include $<

%.app:   %.app-in
	sed -e 's/%APP_NAME%/$(PACKAGE_NAME)/' \
			-e 's/%APP_VERSION%/$(PACKAGE_VERSION)/' < $< > $@

CLEANFILES = $(beam_DATA) $(app_DATA)

