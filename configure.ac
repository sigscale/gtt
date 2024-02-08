## configure.ac
## vim: ts=3
##
## Process this file with autoconf to produce a configure script.
##
## Boilerplate:  standard boilerplate code
##
AC_INIT([gtt], [2.3.1], [issues@sigscale.org])
AC_COPYRIGHT([Copyright (c) 2018-2021 SigScale Global Inc.])
AC_PREREQ(2.63)
AC_CONFIG_SRCDIR([src/gtt_app.erl])
AC_CONFIG_HEADERS([config.h])
AC_LANG([Erlang])
AM_INIT_AUTOMAKE([-Wno-portability])

##
## Options:  control options to configure, support code for the options
##
AC_ARG_ENABLE([debug],
		[AS_HELP_STRING([--disable-debug], [disable debugging (default is no)])])


##
## Programs:  check for programs needed by the configure process,
##            the build process, or by one of the programs being built
##
AC_ERLANG_NEED_ERL
AC_ERLANG_NEED_ERLC
if test -z "${ERLCFLAGS}" ; then
	ERLCFLAGS="-W -v"
fi
if test "x$disable_debug" != xyes ; then
	ERLCFLAGS="$ERLCFLAGS +debug_info"
fi
AC_ERLANG_SUBST_LIB_DIR
if test -z "${ERLANG_INSTALL_LIB_DIR}" ; then
	ERLANG_INSTALL_LIB_DIR=$ERLANG_LIB_DIR
fi
AC_ERLANG_SUBST_ROOT_DIR
AC_PROG_MKDIR_P
AC_PROG_INSTALL
AC_PROG_LN_S
AC_ERLANG_SUBST_INSTALL_LIB_DIR
otpdir=$ERLANG_INSTALL_LIB_DIR/..
appdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION
erldir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/src
beamdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/ebin
eincludedir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/include
wwwdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/priv/www
docdir=$ERLANG_INSTALL_LIB_DIR/$PACKAGE_NAME-$PACKAGE_VERSION/doc
reldir=$ERLANG_INSTALL_LIB_DIR/../releases
AC_SUBST(otp)
AC_SUBST(appdir)
AC_SUBST(erldir)
AC_SUBST(beamdir)
AC_SUBST(eincludedir)
AC_SUBST(wwwdir)
AC_SUBST(reldir)


##
## Libraries:  check for libraries
##
AC_ERLANG_SUBST_ERTS_VER
AC_ERLANG_CHECK_LIB([kernel], [], [AC_MSG_ERROR([kernel was not found!])])
AC_ERLANG_CHECK_LIB([stdlib], [], [AC_MSG_ERROR([stdlib was not found!])])
AC_ERLANG_CHECK_LIB([sasl], [], [AC_MSG_ERROR([sasl was not found!])])
AC_ERLANG_CHECK_LIB([mnesia], [], [AC_MSG_ERROR([mnesia was not found!])])
AC_ERLANG_CHECK_LIB([m3ua], [], [AC_MSG_ERROR([m3ua was not found!])])
AC_ERLANG_CHECK_LIB([sccp], [], [AC_MSG_ERROR([sccp was not found!])])
AC_ERLANG_CHECK_LIB([tcap], [], [AC_MSG_ERROR([tcap was not found!])])
AC_ERLANG_CHECK_LIB([compiler], [], [AC_MSG_ERROR([compiler was not found!])])
AC_ERLANG_CHECK_LIB([inets], [], [AC_MSG_ERROR([inets was not found!])])
AC_ERLANG_CHECK_LIB([snmp], [], [AC_MSG_ERROR([snmp was not found!])])
AC_ERLANG_CHECK_LIB([sigscale_mibs], [], [AC_MSG_ERROR([sigscale_mibs was not found!])])


##
## Headers:  check for header files
##


##
## Typedefs & Structures:  check for typedefs, structures,
##                         and compiler characteristics.
##


##
## Functions:  check for library functions
##


##
## Output:  create output files
## 
AC_OUTPUT([Makefile include/Makefile ebin/Makefile doc/Makefile
		priv/Makefile priv/www/Makefile
		test/Makefile $PACKAGE_NAME.rel sys.config])

