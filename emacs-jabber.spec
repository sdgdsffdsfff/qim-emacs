# -*- coding: latin-1; mode: rpm-spec -*-

%define pkg_name jabber

Version: 0.8
Release: alt0.20080220
Name: emacs-jabber
License: %gpl2plus
Group: Editors
Url: http://emacs-jabber.sourceforge.net
Summary: A minimal jabber client for Emacs

Packager: Emacs Maintainers Team <emacs@packages.altlinux.org>

Source: %name-%version.tar.bz2
Source1: %pkg_name-emacs.el

BuildArch: noarch
Requires: emacs-common emacs-gnus >= 5.10

BuildPreReq: emacs-devel >= 0.0.1-alt2

BuildPreReq: emacs-common
BuildPreReq: rpm-build-licenses
BuildPreReq: emacs-gnus >= 5.10

%description
jabber.el is a minimal Jabber client running under Emacs.

Recommends: xprintidle

%package el
Summary: The Emacs Lisp sources for bytecode included in %name
Group: Development/Other
Requires: %name = %version-%release

%description el
%name-el contains the Emacs Lisp sources for the bytecode
included in the %name package, that extends the Emacs editor.

You need to install %name-el only if you intend to modify any of the
%name code or see some Lisp examples.

%prep
%setup -n %name-%version

%build
makeinfo jabber.texi

%install
mkdir -p %buildroot%_emacslispdir/%pkg_name
install -m 644 *.el %buildroot%_emacslispdir/%pkg_name/

mkdir -p %buildroot%_emacs_sitestart_dir
install -m 644 %SOURCE1 %buildroot%_emacs_sitestart_dir/%pkg_name.el

mkdir -p %buildroot%_infodir
install -m 644 %pkg_name.info %buildroot%_infodir/

%add_lisp_loadpath %buildroot%_emacslispdir/%pkg_name
%byte_recompile_lispdir

mkdir -p %buildroot%_bindir
install -m 755 xmppuri.sh %buildroot%_bindir

%post
%install_info %pkg_name.info

%preun
%uninstall_info %pkg_name.info

%files
%_bindir/*
%dir %_emacslispdir/%pkg_name
%_emacslispdir/%pkg_name/*.elc
%_infodir/%pkg_name.info*
%config(noreplace) %_emacs_sitestart_dir/%pkg_name.el
%doc README AUTHORS NEWS

%files el
%_emacslispdir/%pkg_name/*.el
%doc %pkg_name.texi

%changelog
* Wed Feb 20 2008 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20080220
- cvs-20080220

* Tue Feb 19 2008 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20080219
- cvs-20080219
- All patches dropped (me gain write access to jabber.el CVS)

* Mon Feb 18 2008 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20080218
- cvs-20080218
- Unneeded patches removed (merged in upstream)

* Sun Feb 17 2008 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20080217
- cvs-20080217
- Texinfo documentation source code included in -el package

* Wed Feb  6 2008 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20080206
- cvs-2008206 (build for emacs23)

* Sun Feb  3 2008 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20080203
- cvs-20080203

* Fri Jan 25 2008 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20080122
- cvs-20080122

* Fri Jan 18 2008 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20080118
- cvs-20080118

* Sun Nov 18 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20071117
- cvs-20071117
- Patch1 removed (merged in upstream)

* Wed Nov  7 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20071106
- cvs-20071106
- Patch1 added

* Sun Oct 28 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20071028
- cvs-20071028
- Patch1 removed (replaced in upstream)
- Init script cleanup

* Sat Sep  1 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070831.1
- Patch1 added

* Fri Aug 31 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070831
- CVS-20070831
- Init script cleanup (obsoleted and frustrating code removed)

* Fri Aug 24 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070824
- cvs-20070824

* Sun Aug 19 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070819
- cvs-20070819
- License tag now macro (buildreq to rpm-build-licenses)
- Spec cleanup

* Sat Aug  4 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070804
- Patch1 removed (merged in upstream)

* Thu Jul 12 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070606.1
- Patch1 added

* Wed Jun  6 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070606
- cvs-20070606

* Wed May  9 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070509
- git-20070509 (git://git.catap.ru/emacs-jabber)
- Patch1 removed (merged in upstream)

* Sat Apr 28 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070428
- Patch1 added

* Sat Apr 28 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070428
- cvs-20070428

* Thu Apr 19 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070419
- cvs-20070419
- All patches removed (commited in upstream)

* Mon Feb 19 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070219
- Patch0 added again
- Patch1 added (temporary)
- cvs-20070219

* Thu Feb  1 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070201
- cvs-20070201
- xmppuri.sh handler added

* Mon Jan  8 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070108
- Patch0 removed (fixed in upstream)

* Mon Jan  8 2007 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20070108
- cvs-20070108

* Thu Dec 14 2006 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20061214
- Patch0 replaced by new version

* Tue Dec 12 2006 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20061212
- Long actions patch added (#0)

* Fri Dec  8 2006 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20061208
- jabber-emacs.el additionals

* Sun Nov 19 2006 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20061119
- cvs-alt0.20061119

* Sun Oct 22 2006 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20061022
- cvs-20061022
- Obsolete patch really removed (author claims that he really fix bug)

* Sat Oct 21 2006 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20061021
- cvs-20061021
- Obsolete patch removed

* Fri Oct 13 2006 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20061013
- cvs-20061013

* Sat Aug 26 2006 Terechkov Evgenii <evg@altlinux.ru> 0.8-alt0.20060826
- cvs-20060826

* Thu Mar 02 2006 Eugene Vlasov <eugvv@altlinux.ru> 0.7-alt1
- Initial build for Sisyphus