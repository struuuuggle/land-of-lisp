
;; This is simple http server

;; 16進数で表されたASCIIコードをデコードする
(defun http-char (c1 c2 &optional (default #\space))
  (let ((code (parse-integer
               (coerce (list c1 c2) 'string)
               :radix 16
               :junk-allowed t)))
    (if code
        (code-char code)
      default)))

;; リクエストパラーメータから値を取り出す
;; e.g.
;; (decode-param "foo")     -> "foo"
;;
;; (decode-param "foo%3F")  -> "foo?"
;;
;; (decode-param "foo+bar") -> "foo bar"
(defun decode-param (s)
  (labels ((f (lst)
              (when lst
                (case (car lst)
                  (#\% (cons (http-char (cadr lst) (caddr lst))
                             (f (cdddr lst))))
                  (#\+ (cons #\space (f (cdr lst))))
                  (otherwise (cons (car lst) (f (cdr lst))))))))
    (coerce (f (coerce s 'list)) 'string)))

;; リクエストパラメータのリストをデコードする
;; e.g.
;; (parse-params "name=bob&age=25&gender=male") -> ((NAME . "bob") (AGE . "25") (GENDER . "male"))
(defun parse-params (s)
  (let ((i1 (position #\= s))
        (i2 (position #\& s)))
    (cond (i1 (cons (cons (intern (string-upcase (subseq s 0 i1)))
                          (decode-param (subseq s (1+ i1) i2)))
                    (and i2 (parse-params (subseq s (1+ i2))))))
          ((equal s "") nil)
          (t s))))

;; リクエストヘッダの1行目を読み込み、URLを抜き出す
;; e.g.
;; (extract-url "GET /lolcats.html HTTP/1.1") -> ("lolcats.html")
;;
;; (extract-url "GET /lolcats.html?extra-funny=yes HTTP/1.1") -> ("lolcats.html" (EXTRA-FUNNY . "yes"))
(defun extract-url (s)
  (let* ((url (subseq s
                      (+ 2(position #\space s))
                      (position #\space s :from-end t)))
         (x (position #\? url)))
    (if x
        (cons (subseq url 0 x) (parse-params (subseq url (1+ x))))
      (cons url '()))))

;; リクエストヘッダの2行目以降を読み込み、alistにして返す
;; (get-header (make-string-input-stream "foo: 1
;; bar: abc, 123
;;
;; "))
;; -> ((FOO . "1") (BAR . "abc, 123"))
(defun get-header (stream)
  (let* ((s (read-line stream))
         (h (let ((i (position #\: s)))
              (when i
                (cons (intern (string-upcase (subseq s 0 i)))
                      (subseq s (+ i 2)))))))
    (when h
      (cons h (get-header stream)))))

;; リクエストボディの解析
(defun get-content-params (stream header)
  (let ((length (cdr (assoc 'content-length header))))
    (when length
      (let ((content (make-string (parse-integer length))))
        (read-sequence content stream)
        (parse-params content)))))

;; サーバ関数
;; usage:
;; (serve #'hello-request-handler)
(defun serve (request-handler)
  (let ((socket (socket-server 8080)))
    (unwind-protect
        (loop (with-open-stream (stream (socket-accept socket))
                                (let* ((url    (extract-url (read-line stream)))
                                       (path   (car url))
                                       (header (get-header stream))
                                       (params (append (cdr url)
                                                       (get-content-params stream header)))
                                       (*standard-output* stream))
                                  (funcall request-handler path header params))))
      (socket-server-close socket))))

;; 動的なWebサイトを作る
;; e.g.
;; (hello-request-handler "lolcats" '() '())
;; -> Sorry... I don't know that page.
;;
;; (hello-request-handler "greeting" '() '())
;; -> "<html><form>What is your name?<input name='name' /></form></html>"
;;
;; (hello-request-handler "greeting" '() '((name . "Bob")))
;; -> <html>Nice to mmet you, Bob!</html>
(defun hello-request-handler (path header params)
  (if (equal path "greeting")
      (let ((name (assoc 'name params)))
        (if (not name)
            (progn
              (format t "HTTP/1.1 200 OK~%~%")
              (princ "<html><form>What is your name?<input name='name' /></form></html>"))
          (progn
            (format t "HTTP/1.1 200 OK~%~%")
            (format t "<html>Nice to meet you, ~a!</html>" (cdr name)))))
    (princ "Sorry... I don't know that page.")))
