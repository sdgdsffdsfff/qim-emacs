;;; Extensions for qim chat -*- lexical-binding: t -*-

(require 'json)
(require 'jabber-qim-util)
(require 'jabber-qim-webapi)
(require 'jabber-core)
(require 'jabber-avatar)
(require 'jabber-util)

;; user environment

;;;###autoload
(defvar *jabber-qim-user-vcard-cache*
  (make-hash-table :test 'equal))

;;;###autoload
(defvar *jabber-qim-user-jid-cache*
  '())

;;;###autoload
(defvar *jabber-qim-username-to-jid-cache*
  '())

(defun jabber-qim-users-preload (jc)
  (jabber-qim-api-request-post
   #'(lambda (data conn headers)
       (mapcar #'(lambda (vcard)
                   (add-to-list '*jabber-qim-user-jid-cache*
                                (jabber-jid-symbol (jabber-qim-user-vcard-jid vcard)))
                   (puthash (jabber-qim-user-vcard-jid vcard)
                            vcard *jabber-qim-user-vcard-cache*)
                   (add-to-list '*jabber-qim-username-to-jid-cache*
                                (cons (intern (format "%s - %s"
                                                      (jabber-qim-user-vcard-name vcard)
                                                      (jabber-qim-user-vcard-position vcard)))
                                      (jabber-qim-user-vcard-jid vcard)))) data))
   "getusers"
   "u="
   'applicaion/json))

(add-to-list 'jabber-post-connect-hooks 'jabber-qim-users-preload)

;; extension functions

(defun jabber-qim-object-attributes (object-text)
  (when (string-prefix-p "[obj " object-text)
    (mapcar #'(lambda (kv-text)
                (let ((kv (split-string kv-text "=")))
                  (cons (intern (car kv))
                        (replace-regexp-in-string "\\\"" ""
                                                  (string-join (cdr kv) "=")))))
            (split-string (subseq object-text
                                  5 (1- (length object-text)))))))


(defvar *jabber-qim-emotion-map*
  (make-hash-table :test 'equal))

(defun jabber-qim-get-emotion-by-shortcut (shortcut)
  (gethash shortcut *jabber-qim-emotion-map*))

(defun jabber-qim-load-emotions-from-dir (dir)
  "Load emotions from single directory"
  (let ((resource-xml (xml-parse-file
                       (format "%s/emotions.xml" dir))))
    (mapcar (lambda (face-node)
              (let* ((face-attributes (nth 1 face-node))
                     (face-shortcut (cdr (assoc 'shortcut face-attributes)))
                     (file-org (caddr (nth 3 face-node)))
                     (file-fixed (caddr (nth 5 face-node))))
                (puthash face-shortcut
                         (format "%s/%s" dir file-org)
                         *jabber-qim-emotion-map*)
                ))
            (remove-if-not 'listp
                           (cdddr
                            (cadddr
                             (assoc 'FACESETTING
                                    resource-xml))))))
  )

(defun jabber-qim-load-emotions (emotion-base-dir)
  (mapcar 'jabber-qim-load-emotions-from-dir
          (mapcar #'(lambda (dir)
                      (expand-file-name dir emotion-base-dir))
                  (remove-if #'(lambda (dir)
                                 (or (equal dir ".")
                                     (equal dir "..")))
                             (directory-files emotion-base-dir)))))

(jabber-qim-load-emotions (expand-file-name jabber-qim-local-emotions-directory))

(defun jabber-qim-emotion-image (shortcut)
  (jabber-create-image (jabber-qim-get-emotion-by-shortcut shortcut)))



(defun jabber-qim-view-file-in-directory (file-path)
  (find-file (file-name-directory file-path))
  (revert-buffer t t t)
  (dired-goto-file file-path))

(defun jabber-qim-send-to-chat (data &optional prompt msg-type)
  "Send data to selected (active) chat buffer"
  (let* ((session-muc-alist (jabber-qim-session-muc-vcard-alist))
         (jid (jabber-qim-user-jid-by-completion
               (jabber-read-jid-completing (if (stringp prompt)
                                               prompt
                                             "Select chat buffer: ")
                                           (append (mapcar #'car session-muc-alist)
                                                   (jabber-qim-user-jid-completion-list))
                                           nil
                                           nil
                                           nil
                                           nil
                                           t)))
         (jc (jabber-read-account))
         (muc-jid (cdr (assoc (intern jid)
                              session-muc-alist)))
         (send-function (if muc-jid
                            'jabber-muc-send
                          'jabber-chat-send))
         (buffer (if muc-jid
                     (jabber-muc-create-buffer jc muc-jid)
                   (jabber-chat-create-buffer jc jid))))
    (switch-to-buffer buffer)
    (funcall send-function
             jc
             data
             msg-type)))

(defun jabber-qim-forward-object-action (button)
  (jabber-qim-send-to-chat
   (button-get button :object-text)
   "Forward to: "
   (button-get button :msg-type)))

(defun jabber-qim-insert-file (file-desc body-text face &optional uid)
  "Insert file into chat buffer."
  (insert "\n\n")
  (insert (jabber-propertize
           (format "[File Received: %s; Size: %s; MD5 Checksum: %s] "
                   (cdr (assoc 'FileName
                               file-desc))
                   (cdr (assoc 'FileSize
                               file-desc))
                   (cdr (assoc 'FILEMD5
                               file-desc)))
           'face face))
  (insert "\n")
  (insert-button "View In Directory"
                 :file-desc file-desc
                 :uid (or uid "")
                 'action #'(lambda (button)
                             (lexical-let* ((file-name (cdr (assoc 'FileName
                                                                   (button-get button :file-desc))))
                                            (file-path (format "%s/%s"
                                                               (jabber-qim-local-received-files-cache-dir)
                                                               file-name))
                                            (file-md5 (cdr (assoc 'FILEMD5
                                                                  (button-get button :file-desc))))
                                            (url (format "%s/%s&uid=%s"
                                                         *jabber-qim-file-server*
                                                         (cdr (assoc 'HttpUrl
                                                                     (button-get button :file-desc)))
                                                         (url-hexify-string (button-get button :uid)))))
                               (if (and
                                    (file-exists-p file-path)
                                    (string= file-md5 (secure-hash-file file-path 'md5)))
                                   (jabber-qim-view-file-in-directory file-path)
                                 (web-http-get
                                  #'(lambda (httpc header body)
                                      (if (equal "200" (gethash 'status-code header))
                                          (let ((coding-system-for-write 'binary))
                                            (with-temp-file file-path
                                              (insert body))
                                            (message "File %s downloaded" file-name)
                                            (jabber-qim-view-file-in-directory file-path))
                                        (message "ERROR Downloading %s: %s %s"
                                                 file-name
                                                 (gethash 'status-code header)
                                                 (gethash 'status-string header))))
                                  :url url)))))
  (insert "\t")
  (insert-button "Forward File To..."
                 :object-text body-text
                 :msg-type jabber-qim-msg-type-file
                 'action #'jabber-qim-forward-object-action)
  (insert "\n"))


(defconst jabber-qim-max-image-width 1024)

(defconst jabber-qim-max-image-height 768)


(defun jabber-qim-scale-image-size (width height)
  (let ((scale (max (/ width jabber-qim-max-image-width)
                    (/ height jabber-qim-max-image-height))))
    (if (> scale 1)
        (cons (round (/ width scale))
              (round (/ height scale)))
      (cons width height))))


(defun jabber-qim-parse-image-filename (img-value)
  (car
   (last
    (split-string (find-if
                   #'(lambda (param)
                       (string-prefix-p "file=" param))
                   (split-string
                    (cadr (split-string
                           img-value
                           "[?]"))
                    "&")) "/"))))

(defun jabber-qim-parse-image-type (img-value)
  (let ((ext
         (car
          (last (split-string
                 (jabber-qim-parse-image-filename
                  img-value)
                 "[.]")))))
    (when ext
      (downcase ext))))


(defun jabber-qim-insert-object (object-text face &optional uid)
  "Insert object into chat buffer."
  (let* ((object-attributes (jabber-qim-object-attributes object-text))
         (type (intern (cdr (assoc-string 'type object-attributes))))
         (value (cdr (assoc-string 'value object-attributes))))
    (case type
      ('emoticon
       (let ((image (jabber-qim-emotion-image
                     (replace-regexp-in-string "\\\]" ""
                                               (replace-regexp-in-string "\\\[" "" value)))))
         (if image
             (insert-image
                image
                value)
           (insert (jabber-propertize
                    object-text
                    'face face)))))
      ('image
       (insert "\n\n")
       (let* ((image-size (jabber-qim-scale-image-size (string-to-number
                                                        (cdr (assoc-string 'width object-attributes)))
                                                       (string-to-number
                                                        (cdr (assoc-string 'height object-attributes)))))
              (image-ret (jabber-qim-wget-image value image-size uid))
              (image (cadr image-ret)))
         (if image
             (progn
               (insert-image
                image
                value)
               (insert "\n\n")
               (insert-button "View Image"
                              :image-filepath (caddr image-ret)
                              'action #'(lambda (button)
                                          (let ((file-path (button-get button :image-filepath)))
                                            (when (file-exists-p file-path)
                                              (find-file file-path)
                                              (read-only-mode))))))
           (progn
             (insert (jabber-propertize
                (format "[Image]<%s/%s> " *jabber-qim-file-server* value)
                'face face))
             (insert-button "View Image"
                      :image-url (format "%s/%s" *jabber-qim-file-server* value)
                      :image-ext (jabber-qim-parse-image-type value)
                      :uid (or uid "")
                      'action #'(lambda (button)
                                  (lexical-let ((image-url (button-get button :image-url))
                                                (image-ext (button-get button :image-ext))
                                                (cached-image-file (gethash (button-get button :image-url)
                                                                            *jabber-qim-image-file-cache*)))
                                    (if cached-image-file
                                        (progn
                                          (find-file cached-image-file)
                                          (read-only-mode))
                                      (web-http-get
                                       #'(lambda (httpc header body)
                                           (ignore-errors
                                             (if (equal "200" (gethash 'status-code header))
                                                 (let ((file-path (format "%s/%s.%s"
                                                                          (jabber-qim-local-images-cache-dir)
                                                                          (md5 body)
                                                                          image-ext)))
                                                   (unless (file-exists-p file-path)
                                                     (let ((coding-system-for-write 'binary))
                                                       (with-temp-file file-path
                                                         (insert body)))
                                                     (puthash image-url file-path *jabber-qim-image-file-cache*))
                                                   (find-file file-path)
                                                   (read-only-mode))
                                               (message "ERROR Downloading Image: %s %s"
                                                        (gethash 'status-code header)
                                                        (gethash 'status-string header)))))
                                       :url (format "%s&uid=%s"
                                                    image-url
                                                    (url-hexify-string (button-get button :uid)))))))))))
       (insert "\t")
       (insert-button "Forward Image To..."
                      :object-text object-text
                      :msg-type jabber-qim-msg-type-default
                      'action #'jabber-qim-forward-object-action)
       (insert "\n\n"))
      ('url
       (insert (jabber-propertize
                value
                'face face)))
      (t
       (insert (jabber-propertize
                object-text
                'face face))))))

(defun jabber-qim-wget-image (url-path &optional image-size uid)
  (let ((image-file (gethash url-path *jabber-qim-image-file-cache*)))
    (unless image-file
      (let ((image-download-path (format "%s/%s"
                                         (jabber-qim-local-images-cache-dir)
                                         (jabber-qim-parse-image-filename url-path))))
        (ignore-errors
          (call-process (executable-find "wget") nil nil nil
                        "-T" "1.0"
                        "-O" image-download-path
                        (if image-size
                            (format "%s/%s&w=%s&h=%s&uid=%s"
                                    *jabber-qim-file-server* url-path
                                    (car image-size)
                                    (cdr image-size)
                                    (url-hexify-string
                                     (or uid "")))
                          (format "%s/%s&uid=%s" *jabber-qim-file-server*
                                  url-path (url-hexify-string
                                            (or uid ""))))))
        (let ((image-file-size (nth 7 (file-attributes image-download-path))))
          (when (and image-file-size
                     (> image-file-size 0))
            (setq image-file image-download-path)
            (puthash url-path image-download-path *jabber-qim-image-file-cache*)
            ))))
    (when image-file
      (list (secure-hash-file image-file 'md5)
            (jabber-create-image image-file)
            image-file))))


;; (defun jabber-qim-load-image (url-path &optional image-size uid)
;;   (lexical-let ((latch (make-one-time-latch))
;;                 (image nil)
;;                 (ret nil))
;;     (unless (setq image (gethash url-path *jabber-qim-image-file-cache*))
;;       (web-http-get
;;        #'(lambda (httpc header body)
;;            (ignore-errors
;;              (when (and body
;;                         (equal "200" (gethash 'status-code header)))
;;                (let ((file-path (format "%s/%s.%s"
;;                                         (jabber-qim-local-images-cache-dir)
;;                                         (md5 body)
;;                                         (jabber-qim-parse-image-type url-path))))
;;                  (unless (file-exists-p file-path)
;;                    (let ((coding-system-for-write 'binary))
;;                      (with-temp-file file-path
;;                        (insert body))))
;;                  (setq image file-path)
;;                  (puthash url-path file-path *jabber-qim-image-file-cache*)
;;                  (setq ret (md5 body)))))
;;            (apply-partially #'nofify latch))
;;        :url (if image-size
;;                 (format "%s/%s&w=%s&h=%s&uid=%s"
;;                         *jabber-qim-file-server* url-path
;;                         (car image-size)
;;                         (cdr image-size)
;;                         (url-hexify-string
;;                          (or uid "")))
;;               (format "%s/%s&uid=%s" *jabber-qim-file-server*
;;                       url-path (url-hexify-string
;;                                 (or uid "")))))
;;       (wait latch 0.5))
;;     (when image
;;       (list (secure-hash-file image 'md5)
;;             (jabber-create-image image)
;;             image))))

(defun jabber-qim-load-file (file-desc)
  (lexical-let ((file-path (format "%s/%s"
                           (jabber-qim-local-received-files-cache-dir)
                           (cdr (assoc 'FileName file-desc))))
        (url (format "%s/%s" *jabber-qim-file-server* (cdr (assoc 'HttpUrl file-desc)))))
    (web-http-get
     #'(lambda (httpc header body)
         (let ((coding-system-for-write 'binary))
             (with-temp-file file-path
               (insert body))))
     :url url
     )
    `((:saved-path . ,file-path)
      (:filename . ,(cdr (assoc 'FileName file-desc)))
      (:link . ,url)
      (:size . ,(cdr (assoc 'FileSize file-desc)))
      (:md5 . ,(cdr (assoc 'FILEMD5 file-desc))))
    ))

(defconst jabber-qim-msg-type-file "5"
  "Message is a file")

(defconst jabber-qim-msg-type-default "1"
  "Normal messages")

(defconst jabber-qim-max-send-file-size (* 10 1024 1024)
  "Max send file size set to 10MB")


(cl-defun jabber-qim-send-file (filename jc jid send-function &optional chat-buffer)
  (interactive
   (append (list (read-file-name (let ((current-jid (or jabber-group
                                                        jabber-chatting-with)))
                                   (if current-jid
                                       (format "Sending File or Image to %s: "
                                               (jabber-jid-displayname current-jid))
                                     "Send File or Image: "))))
           (jabber-qim-interactive-send-argument-list "To chat: ")))
  (if (<= (nth 7 (file-attributes filename))
          jabber-qim-max-send-file-size)
      (let ((file-buffer (find-file-noselect filename t)))
        (web-http-post
         #'(lambda (httpc headers body)
             (let ((jabber-group jid)
                   (jabber-chatting-with jid)
                   (image (ignore-errors
                            (create-image filename)))
                   (msg-id (jabber-message-uuid)))
               (when chat-buffer
                 (switch-to-buffer chat-buffer))
               (funcall send-function jc
                        (if image
                            (let ((size (image-size image t)))
                              (format "[obj type=\"image\" value=\"%s&msgid=%s\" width=%s height=%s]"
                                      (string-trim (url-unhex-string body))
                                      msg-id
                                      (round (car size))
                                      (round (cdr size))))
                          (json-encode `((:HttpUrl . ,(format "%s&msgid=%s"
                                                              (string-trim (url-unhex-string body))
                                                              msg-id))
                                         (:FileName . ,(file-name-nondirectory filename))
                                         (:FILEID . ,(jabber-message-uuid))
                                         (:FILEMD5 . ,(secure-hash-file filename 'md5))
                                         (:FileSize . ,(file-size-human-readable
                                                        (nth 7 (file-attributes filename)))))))
                        (if image
                            jabber-qim-msg-type-default
                          jabber-qim-msg-type-file)
                        msg-id)))
         :url (format "%s/cgi-bin/file_upload.pl" *jabber-qim-file-server*)
         :mime-type 'multipart/form-data
         :data `(("file" . ,file-buffer)))
        (kill-buffer file-buffer))))

(define-key jabber-global-keymap "\C-f" 'jabber-qim-send-file)


(defun jabber-qim-interactive-send-argument-list (&optional prompt)
  (let* ((jc (jabber-read-account))
         (jid-at-point (or
                        (bound-and-true-p jabber-chatting-with)
                        (bound-and-true-p jabber-group)))
         (session-muc-alist (jabber-qim-session-muc-vcard-alist))
         (jid (or
               jid-at-point
               (jabber-qim-user-jid-by-completion
                (jabber-read-jid-completing (if (stringp prompt)
                                                prompt
                                              "Select chat: ")
                                            (append (mapcar #'car session-muc-alist)
                                                    (jabber-qim-user-jid-completion-list))
                                            nil
                                            nil
                                            nil
                                            nil
                                            t))))
         (muc-jid (if (and
                       jid-at-point
                       (jabber-qim-muc-jid-p jid-at-point))
                      jid-at-point
                    (cdr (assoc (intern jid)
                                session-muc-alist))))
         (send-function (if muc-jid
                            'jabber-muc-send
                          'jabber-chat-send))
         (buffer (if muc-jid
                     (jabber-muc-create-buffer jc muc-jid)
                   (jabber-chat-create-buffer jc jid))))
    (list jc
          (or muc-jid
              jid)
          send-function
          buffer)))

(defun jabber-qim-send-screenshot (jc jid send-function &optional chat-buffer)
  (interactive
   (jabber-qim-interactive-send-argument-list "Send screenshot to chat: "))
  (let ((image-file (format "%s/%s.png"
                            (jabber-qim-local-screenshots-dir)
                            (jabber-message-uuid)))
        (screencapture-executable (executable-find
                                   (if (eq system-type 'darwin)
                                       "screencapture"
                                     "import")))
        (current-jid (or jabber-group
                         jabber-chatting-with)))
    (if screencapture-executable
        (progn
          (when current-jid
            (message "Sending screenshot to %s:" (jabber-jid-displayname current-jid)))
          (if (equal 0 (ignore-errors
                         (if (eq system-type 'darwin)
                             (call-process screencapture-executable nil nil nil
                                           "-i" image-file)
                           (call-process screencapture-executable nil nil nil
                                         image-file))))
              (jabber-qim-send-file image-file jc jid send-function chat-buffer)
            (message "Screen capture failed.")))
      (message "Screen capture exec not available."))))

(define-key jabber-global-keymap "\C-s" 'jabber-qim-send-screenshot)


(defun jabber-qim-chat-send-screenshot (jc chat-with &optional chat-buffer)
  (interactive
   (list (jabber-read-account)
         jabber-chatting-with
         (current-buffer)))
  (if chat-with
      (jabber-qim-send-screenshot jc chat-with 'jabber-chat-send chat-buffer)
    (error "Not in CHAT buffer")))


(defun jabber-qim-chat-send-file (jc chat-with filename &optional chat-buffer)
  (interactive
   (list (jabber-read-account)
         jabber-chatting-with
         (read-file-name "Send File or Image: ")
         (current-buffer)))
  (if chat-with
      (if (<= (nth 7 (file-attributes filename))
              jabber-qim-max-send-file-size)
          (jabber-qim-send-file filename jc chat-with 'jabber-chat-send chat-buffer)
        (error "File size exceeds maximum: %s"
           (file-size-human-readable jabber-qim-max-send-file-size)))
    (error "Not in CHAT buffer")))

(defun jabber-qim-chat-start-groupchat (jc
                                        chat-with
                                        invited-members
                                        &optional default-groupchat-name)
  (interactive
   (list (jabber-read-account)
         (when (bound-and-true-p jabber-chatting-with)
           jabber-chatting-with)
         (let ((initial-invites '())
               (invited nil))
           (while (> (length (setq invited
                                   (jabber-qim-user-jid-by-completion
                                    (jabber-read-jid-completing "Invite (leave blank for end of input): "
                                                                (jabber-qim-user-jid-completion-list)
                                                                nil nil nil nil t t))))
                     0)
             (add-to-list 'initial-invites invited))
           initial-invites)
         ))
  (let* ((chatroom-members
          (delete-dups
           (-filter #'(lambda (x)
                        x)
                    (append (list (jabber-qim-jid-nickname (plist-get
                                                            (fsm-get-state-data jabber-buffer-connection)
                                                            :original-jid))
                                  (jabber-qim-jid-nickname jabber-chatting-with))
                            (mapcar #'jabber-qim-jid-nickname invited-members)))))
         (groupchat-name
          (or default-groupchat-name
              (read-string "New Group Name: "
                           (string-join
                            (if (> (length chatroom-members) 4)
                                (append (subseq
                                         chatroom-members
                                         0 4)
                                        (list "..."))
                              chatroom-members)
                            ","            
                            )                      
                           nil nil t)))
         (my-jid (plist-get (fsm-get-state-data jabber-buffer-connection) :original-jid))
         (muc-jid (format "%s@%s.%s"
                          (secure-hash 'md5 (format "%s,%s,%s,%s"
                                                    my-jid
                                                    groupchat-name
                                                    chat-with
                                                    (format-time-string "%s")))
                          *jabber-qim-muc-sub-hostname*
                          *jabber-qim-hostname*)))
    (when (or invited-members
              chat-with)
      (puthash muc-jid
               (append (when chat-with
                         (list chat-with))
                       invited-members)
               *jabber-qim-muc-initial-members*))
    (jabber-qim-api-request-post
     (lambda (data conn headers)
       (when (equal "200" (gethash 'status-code headers))
         (puthash (jabber-jid-user muc-jid)
                  `((SN . ,groupchat-name)
                    (MN . ,(jabber-jid-user muc-jid)))
                  *jabber-qim-muc-vcard-cache*)
         (jabber-qim-muc-join jc muc-jid t)))
     "setmucvcard"
     (json-encode (vector `((:muc_name . ,(jabber-jid-user muc-jid))
                            (:nick . ,groupchat-name))))
     'applicaition/json)))

(define-key jabber-global-keymap "\C-g" 'jabber-qim-chat-start-groupchat)

(defun jabber-qim-message-type (message)
  (cdr (assoc 'msgType (jabber-xml-node-attributes
                        (car
                         (jabber-xml-get-children message 'body))))))

(defun jabber-qim-body-parse-file (body)
  (let ((file-desc (ignore-errors
                     (json-read-from-string body))))
    (when (and file-desc
               (cdr (assoc 'FileName file-desc))
               (cdr (assoc 'HttpUrl file-desc)))
      file-desc)))

(provide 'jabber-qim-chat)