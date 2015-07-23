**基于jabber.el的emacs qim客户端**
===============================


## **开发分支**
qim-emacs

## **安装方法**
**依赖**： Linux操作系统，openssl，autoconf，automake，emacs uuid模块

Make sure that autoconf and automake are installed and run

    autoreconf -i
    ./configure
    make

You can specify which emacs you want to use:
./configure EMACS=emacs-or-xemacs-21.4

You can also install jabber.el by hand.  Put all .el files somewhere
in your load-path, or have your load-path include the directory
they're in.

After installation by either method, add (load "jabber-autoloads") to
your .emacs file.


## **参考配置**

    (add-to-list 'load-path "~/Documents/sources/emacs-jabber") ; 本工程目录

    (setq jabber-qim-pubkey-file
        "~/Documents/sources/emacs-jabber/resources/qtalk_pub_key.pem") ; 公钥文件路径

    (load "jabber-autoloads")

    ; (setq jabber-debug-log-xml t)

    (setq jabber-invalid-certificate-servers '("qt.corp.qunar.com"))

    (setq starttls-extra-arguments  '("--insecure"))
    (setq jabber-history-enabled t)
    (setq jabber-use-global-history nil)
    (setq jabber-history-muc-enabled t)
    (setq jabber-history-dir "~/qtalk-logs")
    (setq jabber-muc-colorize-foreign t) ;; nick color


    (setq jabber-alert-presence-message-function
        (lambda (WHO OLDSTATUS NEWSTATUS STATUSTEXT)
        nil))


    (setq jabber-muc-autojoin
        '("qtalk客户端开发群@conference.ejabhost1"))

    ;; account list
    (setq jabber-account-list
    `(
        ("geng.li@ejabhost1"
        (:network-server . "qt.corp.qunar.com")
        (:port . "5222")
        (:password . ,(jabber-qim-password "域用户名" "域密码")))))

    (jabber-connect-all)



