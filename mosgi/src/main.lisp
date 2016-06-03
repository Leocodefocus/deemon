#|
Author:Simon Koch <s9sikoch@stud.uni-saarland.de>
This file is (as the name suggests) the main file. It parses
the passed cmd arguments and starts the whole service and
waits/responds for commands and executes given commands
|#
(in-package :de.uni-saarland.syssec.mosgi)


(defparameter *legal-communication-chars*
  '((#\D . :START-DIFF) 
    (#\K . :KILL-YOURSELF) 
    (#\F . :FINISHED-DIFF)))


(defparameter *listen-port* 4242)


(defparameter *target-ip*  "127.0.0.1")


(defparameter *php-session-diff-state* nil)


(defparameter *file-diff-state* nil) 


(opts:define-opts
  (:name :php-session-folder
	 :description "absolute path on the guest system to the folder where the relevant php-sessions are stored"
	 :short #\P
	 :long "php-session-folder"
	 :arg-parser #'identity)
  (:name :xdebug-trace-file
	 :description "absolute path to the folder containing machine readable trace generated by xdebug on the guest system"
	 :short #\x
	 :long "xdebug-trace-folder"
	 :arg-parser #'identity)
  (:name :port
	 :description "the port mosgi shall listen on for a command connection"
	 :short #\p
	 :long "port"
	 :arg-parser #'parse-integer)
  (:name :interface
	 :description "the ip-address mosgi shall listen on for a command connection"
	 :short #\i
	 :long "interface"
	 :arg-parser #'identity)
  (:name :target-system-ip
	 :description "the ip-address of the guest system to connect to via ssh - sshd needs to be running"
	 :short #\t
	 :long "target-system"
	 :arg-parser #'identity)
  (:name :target-system-root
	 :description "the root user of the guest system"
	 :short #\r
	 :long "target-root"
	 :arg-parser #'identity)
  (:name :target-system-pwd
	 :description "the password for the root account of the guest system"
	 :short #\c
	 :long "host-pwd"
	 :arg-parser #'identity))
    

(defun make-diff (php-session-folder xdebug-trace-folder user host pwd)
  (FORMAT T "running php session analysis~%")
  (diff:add-next-state-* *php-session-diff-state* 
			 (diff:make-php-session-history-state php-session-folder user host pwd))
  (FORMAT T "finsihed php session analysis~%")
  (cl-fad:with-open-temporary-file (xdebug-tmp-stream :direction :io :element-type 'character)
    (FORMAT T "running xdebug trace analysis~%")
    (ssh:scp (xdebug:get-xdebug-trace-file (ssh:folder-content-guest xdebug-trace-folder
								     user host pwd))
	     (pathname xdebug-tmp-stream) user host pwd)
    (finish-output xdebug-tmp-stream)
    (ssh:convert-to-utf8-encoding (namestring (pathname xdebug-tmp-stream))) ;this is just because encoding is stupid
    (diff:add-next-state-* *file-diff-state* 
			   (diff:make-file-history-state 
			    (xdebug:get-changed-files-paths 
			     (xdebug:make-xdebug-trace xdebug-tmp-stream))
			    user host pwd))
    (FORMAT T "finished xdebug analysis~%")))


(defun main ()
  (handler-case
      (multiple-value-bind (options free-args)
	  (opts:get-opts)
	(declare (ignore free-args))
	(FORMAT T "Congratulation you started mosgi - a program which will most likely:~%")
	(FORMAT T "- crash your computer~%")
	(FORMAT T "- publish your personal information on /b/~%")
	(FORMAT T "- sell you firstborn (probably also on /b/~%")
	(FORMAT T "Furthermore it will do/use:~%")
	(FORMAT T "listen on ~a:~a~%" (getf options :interface) (getf options :port))
	(FORMAT T "target ssh ~a@~a using password ~a~%" (getf options :target-system-root) (getf options :target-system-ip) (getf options :target-system-pwd))
	(FORMAT T "xdebug-trace-folder: ~a~%" (getf options :xdebug-trace-file))
	(FORMAT T "php-session-folder: ~a~%" (getf options :php-session-folder))
	(com:with-connected-communication-handler (handler (getf options :interface) (getf options :port))
	  (do ((received-order (com:receive-character handler)
			       (com:receive-character handler)))
	      ((char= (car (find :KILL-YOURSELF *legal-communication-chars* :key #'cdr)) received-order) nil)
	    (let ((*file-diff-state* (make-instance 'diff:state-trace))
		  (*php-session-diff-state* (make-instance 'diff:state-trace)))
	      (FORMAT T "Received Command: ~a~%" (cdr (find received-order *legal-communication-chars* :key #'car)))
	      (ecase (cdr (find received-order *legal-communication-chars* :key #'car))
		(:START-DIFF 
		 (read-char)
		 (FORMAT T "~%")
		 (make-diff (getf options :php-session-folder) 
			    (getf options :xdebug-trace-file)
			    (getf options :target-system-root)
			    (getf options :target-system-ip)
			    (getf options :target-system-pwd))))
	      (FORMAT T "updatedstates:~%~a~%~%~a" *file-diff-state* *php-session-diff-state*)
	      (com:send-character handler (car (find :FINISHED-DIFF *legal-communication-chars* :key #'cdr)))))))
    (unix-opts:unknown-option (err)
      (declare (ignore err))
      (opts:describe
       :prefix "This program is the badass doing all the work to differentiate state changes after actions on webapplications - kneel before thy master"
       :suffix "so that's how it works…"
       :usage-of "run.sh"))))



(main)
