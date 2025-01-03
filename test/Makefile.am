## Makefile.am
## vim: ts=3
##
## Process this file with automake to produce Makefile.in

testmods = gtt_api_SUITE

check_DATA = .dialyzer_ok .common_test_ok

DIA_ARGS =
CT_ARGS = -spec test.spec

.dialyzer_ok:
	dialyzer ${DIA_ARGS} --src $(top_srcdir)/src

%.beam:$(top_srcdir)/test/%.erl
	$(ERLC) $(ERLCFLAGS) -I $(top_srcdir)/include $<

.common_test_ok:	$(addsuffix .beam, $(testmods))
	@if [ ! -d log ]; then mkdir log; fi
	@if [ ! -f ct.cfg ]; then cp $(top_srcdir)/test/ct.cfg .; fi
	@if [ ! -f test.spec ]; then cp $(top_srcdir)/test/test.spec .; fi
	ct_run -no_auto_compile -pa $(top_builddir)/ebin \
			-logdir log -config ct.cfg -dir . \
			$(CT_ARGS) \
			-erl_args -noshell -sname $(LOGNAME)-ct

clean-local:
	-rm -r log/*

