;;; QTalk extension for groupchats. -*- lexical-binding: t -*-

;; jabber-qim-muc.el 

;; Copyright (C) 2018 - Angus Lee - angus.lee8329@gmail.com

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


(require 'json)
(require 'jabber-qim-util)
(require 'jabber-qim-webapi)

(require 'jabber-core)
(require 'jabber-util)

;;;###autoload
(defvar *jabber-qim-muc-vcard-cache*
  (make-hash-table :test 'equal))

(defvar *jabber-qim-muc-initial-members*
  (make-hash-table :test 'equal))

(defvar *jabber-qim-user-muc-room-jid-list*
  '())

;;;###autoload
(defcustom jabber-qim-autojoin-properties nil
  "Muc autojoin properties"
  :group 'jabber-chat
  :type '(repeat (string :tag "JID of QIM chatroom")))

(defconst *qim-autojoin-settings-file*
  "~/.qim-autojoin.el")


(defun jabber-qim-session-muc-vcards ()
  (let ((ret '()))
    (maphash #'(lambda (key value)
                 (when value
                     (add-to-list 'ret value)))
             *jabber-qim-muc-vcard-cache*)
    ret))

(defun jabber-qim-session-muc-vcard-alist ()
  (mapcar #'(lambda (vcard)
              (cons (intern (jabber-qim-muc-vcard-group-display-name vcard))
                    (jabber-qim-muc-vcard-group-jid vcard)))
          (jabber-qim-session-muc-vcards)))


(when (file-exists-p *qim-autojoin-settings-file*)
  (ignore-errors
    (load-file *qim-autojoin-settings-file*)))

(defun jabber-qim-save-qim-muc-autojoin-settings ()
  (interactive)
  (let ((coding-system-for-write 'no-conversion))
    (with-temp-file *qim-autojoin-settings-file*
      (insert (format "(setq jabber-qim-autojoin-properties '%s)"
                      (prin1-to-string jabber-qim-autojoin-properties)))))
  t)

(add-hook 'jabber-post-disconnect-hook
          'jabber-qim-save-qim-muc-autojoin-settings)

(add-to-list 'kill-emacs-query-functions
		     'jabber-qim-save-qim-muc-autojoin-settings)


(defun jabber-qim-user-muc-join-all (jc)
  (jabber-send-sexp-if-connected jc
                                 `(presence
                                   ((to . ,(format "%s.%s"
                                                   *jabber-qim-muc-sub-hostname*
                                                   *jabber-qim-domain*)))
                                   (x
                                    ((xmlns . "http://jabber.org/protocol/muc#presence_all"))))))


(defun jabber-qim-user-muc-preload (jc)
  (setq *jabber-qim-user-muc-room-jid-list* '())
  (jabber-send-iq jc (format "%s.%s"
                             *jabber-qim-muc-sub-hostname*
                             *jabber-qim-domain*)
                  "get"
                  '(query ((xmlns . "http://jabber.org/protocol/muc#user_mucs")))
                  #'(lambda (jc xml-data closure-data)
                      (let ((muc-rooms (mapcar #'cadr (cddar (jabber-xml-get-children xml-data 'query)))))
                        (jabber-qim-api-request-post
                         #'(lambda (data conn headers)
                             (when (equal "200" (gethash 'status-code headers))
                               (let ((muc-vcards (ignore-errors
                                                   (cdr (assoc 'data data)))))
                                 (mapcar #'(lambda (muc-vcard)
                                             (add-to-list '*jabber-qim-user-muc-room-jid-list*
                                                          (cons (intern (jabber-qim-muc-vcard-group-display-name muc-vcard))
                                                                (jabber-qim-muc-vcard-group-jid muc-vcard)))
                                             
                                             (let* ((muc-jid (jabber-qim-muc-vcard-group-jid muc-vcard))
                                                    (muc-properties (cdr (assoc-string muc-jid
                                                                                       jabber-qim-autojoin-properties))))
                                               (puthash (jabber-jid-user muc-jid)
                                                        muc-vcard
                                                        *jabber-qim-muc-vcard-cache*)
                                               
                                               (when (cdr (assoc :silence muc-properties))
                                                 (unless (find muc-jid *jabber-silenced-groupchats* :test 'equal)
                                                   (add-to-list '*jabber-silenced-groupchats*
                                                                muc-jid)))))
                                         muc-vcards)))
                             (jabber-qim-user-muc-join-all jc))
                         "getmucvcard"
                         (json-encode
                          (mapcar #'(lambda (muc)
                                      (let ((muc-jid (format "%s@%s"
                                                             (cdr (assoc 'name muc))
                                                             (cdr (assoc 'host muc)))))
                                        `((:muc_name . ,(jabber-jid-user muc-jid))
                                          (:version . 0))))
                                  muc-rooms))
                         'application/json
                         (jabber-qim-api-connection-auth-info jc))
                        (mapcar #'(lambda (muc)
                                    (jabber-send-iq jc
                                                    (format "%s@%s"
                                                            (cdr (assoc 'name muc))
                                                            (cdr (assoc 'host muc)))
                                                    "get"
                                                    '(query ((xmlns . "http://jabber.org/protocol/muc#register")))
                                                    #'(lambda (jc xml-data closure-data)
                                                        (let ((muc-jid (jabber-xml-get-attribute xml-data 'from))
                                                              (muc-user-affiliations
                                                               (jabber-qim-muc-parse-affiliations
                                                                (car (jabber-xml-get-children xml-data 'query)))
                                                               ))
                                                          (mapcar #'(lambda (user-affiliation)
                                                                      (jabber-muc-modify-participant muc-jid
                                                                                                     (jabber-jid-displayname
                                                                                                      (plist-get user-affiliation 'jid))
                                                                                                     user-affiliation))
                                                                  muc-user-affiliations)))
                                                    nil
                                                    nil
                                                    nil))
                                muc-rooms))
                      )
                  nil
                  #'(lambda (jc xml-data closure-data)
                      (message "%s" closure-data))
                  "MUC preload failed"))

(defun jabber-qim-muc-set-topic (jc muc-jid topic)
  (interactive
   (jabber-muc-argument-list
    (list (jabber-read-with-input-method "New topic: " jabber-muc-topic))))
  (jabber-qim-api-request-post
   (lambda (data conn headers)
     (unless (equal "200" (gethash 'status-code headers))
       (message "Set muc topic failed. Response: %s" data)))
   "setmucvcard"
   (json-encode (vector `((:muc_name . ,(jabber-jid-user muc-jid))
                          (:title . ,topic))))
   'application/json
   (jabber-qim-api-connection-auth-info jc)))

(defun jabber-qim-muc-set-name (jc muc-jid name)
  (interactive
   (jabber-muc-argument-list
    (list (jabber-read-with-input-method "New group name: "
                                         (jabber-qim-muc-vcard-group-display-name
                                          (jabber-qim-get-muc-vcard jabber-group))))))
  (jabber-qim-api-request-post
   (lambda (data conn headers)
     (unless (equal "200" (gethash 'status-code headers))
       (message "Set muc name failed. Response: %s" data)))
   "setmucvcard"
   (json-encode (vector `((:muc_name . ,(jabber-jid-user muc-jid))
                          (:nick . ,name))))
   'application/json
   (jabber-qim-api-connection-auth-info jc)))


;;;###autoload (autoload 'jabber-qim-muc-join "jabber-qim-extension" "Join a qim MUC chatroom" t)
(cl-defun jabber-qim-muc-join (jc muc-jid &optional popup)
  "Join a qim MUC chatroom"
  (interactive
   (list (jabber-read-account)
         (let ((muc-name
                (jabber-read-jid-completing "Join group: "
                                            (mapcar #'car
                                                    (-filter #'(lambda (muc)
                                                                 (not (find (cdr muc)
                                                                            (mapcar #'car *jabber-active-groupchats*)
                                                                            :test 'string=)))
                                                             *jabber-qim-user-muc-room-jid-list*))
                                            nil nil nil nil t)))
           (if (assoc-string muc-name
                             *jabber-qim-user-muc-room-jid-list*)
               (cdr (assoc-string muc-name
                                  *jabber-qim-user-muc-room-jid-list*))
             muc-name))
         t))
  (if (jabber-qim-muc-jid-p muc-jid)
      (jabber-qim-api-request-post
       #'(lambda (data conn headers)
           (unless (gethash (jabber-jid-user muc-jid)
                            *jabber-qim-muc-vcard-cache*)
             (puthash (jabber-jid-user muc-jid)
                      (if (and (equal "200" (gethash 'status-code headers))
                               (ignore-errors
                                 (nth 0 (cdr (assoc 'data data)))))
                          (nth 0
                               (cdr (assoc 'mucs
                                           (nth 0 (cdr (assoc 'data data))))))
                        `((SN . ,(jabber-jid-user muc-jid))
                          (MN . ,(jabber-jid-user muc-jid))
                          (MT . "")))
                      *jabber-qim-muc-vcard-cache*))
           (jabber-muc-join jc
                            muc-jid
                            (jabber-muc-read-my-nickname jc muc-jid t)
                            popup)
           (with-current-buffer (jabber-muc-create-buffer jc muc-jid)
             (setq jabber-muc-topic (jabber-qim-muc-vcard-group-topic
                                     (gethash (jabber-jid-user muc-jid)
                                              *jabber-qim-muc-vcard-cache*)))))
       "domain/get_muc_vcard"
       (json-encode (vector
                     `((:domain . ,(jabber-qim-jid-domain muc-jid))
                       (:mucs .
                              ,(vector `((:muc_name . ,(jabber-jid-user muc-jid))
                                         (:version . 0)))))))
       'application/json
       (jabber-qim-api-connection-auth-info jc))
    ;; Fallback
    (jabber-muc-join jc muc-jid
                     (jabber-muc-read-my-nickname jc muc-jid)
                     popup)))

(define-key jabber-global-keymap "\C-m" 'jabber-qim-muc-join)


(defun jabber-qim-muc-accept-invite (xml-data who mode)
  "Accept QIM MUC invitation automatically"
  (dolist (x (jabber-xml-get-children xml-data 'x))
    (when (string= (jabber-xml-get-attribute x 'xmlns) "http://jabber.org/protocol/muc#user")
      (let ((invitation (car (jabber-xml-get-children x 'invite)))
            (group (jabber-xml-get-attribute xml-data 'from)))
        (when (and invitation
                   (jabber-qim-muc-jid-p group))
          (jabber-qim-muc-join jabber-buffer-connection group)
          (return t))))))


;;;###autoload (autoload 'jabber-qim-get-muc-vcard "jabber-qim-extension" "Return MUC vcard" t)
(defun jabber-qim-get-muc-vcard (muc-jid)
  "Return MUC vcard"
  (and
   muc-jid
   (jabber-qim-muc-jid-p muc-jid)
   (or (gethash (jabber-jid-user muc-jid) *jabber-qim-muc-vcard-cache*)
       `((SN . ,(jabber-jid-user muc-jid))
         (MN . ,(jabber-jid-user muc-jid))))))

(defun jabber-qim-muc-parse-affiliations (x-mucs)
  (mapcar
   #'(lambda (item)
       (apply 'nconc (mapcar (lambda (prop) (list (car prop) (cdr prop)))
                             (jabber-xml-node-attributes
                              item))))
   (jabber-xml-get-children x-mucs 'm_user)))


(defun jabber-qim-muc-send-screenshot (jc group)
  (interactive
   (jabber-muc-argument-list))
  (jabber-qim-send-screenshot jc group 'jabber-muc-send))


(defun jabber-qim-muc-send-file (jc group filename)
  (interactive
   (jabber-muc-argument-list
    (list (read-file-name "Send File or Image: "))))
  (if (<= (nth 7 (file-attributes filename))
          jabber-qim-max-send-file-size)
      (jabber-qim-send-file filename jc group 'jabber-muc-send)
    (error "File size exceeds maximum: %s"
           (file-size-human-readable jabber-qim-max-send-file-size))))

(provide 'jabber-qim-muc)
