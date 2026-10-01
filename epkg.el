;;; epkg.el --- Make-based package manager  -*- lexical-binding: t -*-

;; Copyright (C) 2026 by dickmao
;;
;; Author: dickie smalls <richard@commandlinesystems.com>
;; Version: 0.0.1
;; URL: https://github.com/dickmao/epkg.git
;; Package-Requires: ((emacs "29.1"))

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

(require 'package)
(require 'cl-lib)
(require 'url-parse)

(defgroup epkg nil
  "Make-based package manager."
  :group 'applications)

(defvar epkg-main)

(defun epkg-desc ()
  (with-temp-buffer
    (insert-file-contents epkg-main)
    (package-buffer-info)))

(defun epkg-dir ()
  (expand-file-name (format "%s.%s" emacs-major-version emacs-minor-version) "epkg"))

(defun epkg-name ()
  (symbol-name (package-desc-name (epkg-desc))))

(defun epkg-name-version ()
  "What package.el calls the full name."
  (concat (epkg-name) "-"
	  (package-version-join (package-desc-version (epkg-desc)))))

(defun epkg-inception ()
  "To get a -pkg.el file, you need to run `package-unpack'.
To run `package-unpack', you need a -pkg.el."
  (let ((pkg-desc (epkg-desc))
	(pkg-dir (expand-file-name (epkg-name-version) (epkg-dir))))
    (ignore-errors (delete-directory pkg-dir t))
    (make-directory pkg-dir t)
    (copy-file epkg-main (expand-file-name (file-name-nondirectory epkg-main) pkg-dir))
    (package--make-autoloads-and-stuff pkg-desc pkg-dir)))

(defun epkg--collect-requires (form &optional reqs)
  (pcase form
    (`(epkg-require ',sym ,(and url (pred stringp)))
     (let ((prev (alist-get sym reqs)))
       (when (and prev (not (equal prev url)))
	 (error "epkg-require: %s is both %s and %s" sym prev url))
       (cl-pushnew (cons sym url) reqs :test #'equal)))
    (_ (while (consp form)
	 (setq reqs (epkg--collect-requires (pop form) reqs)))))
  reqs)

;;;###autoload
(defmacro epkg-require (sym _url)
  "This has to effectively `require' SYM."
  `(require ,sym))

(defun epkg-prune (reqs)
  "Delete packages in `epkg-dir' unneeded by REQS or Package-Requires."
  (let ((package-user-dir (expand-file-name "elpa" (epkg-dir)))
	package-directory-list package-alist)
    (package-load-all-descriptors)
    (let ((keep (package--get-deps
		 (append (mapcar #'car reqs)
			 (mapcar #'car (package-desc-reqs (epkg-desc)))))))
      (dolist (pkg package-alist)
	(unless (memq (car pkg) keep)
	  (dolist (desc (cdr pkg))
	    (delete-directory (package-desc-dir desc) t)))))))

(defun epkg--git (dir &rest args)
  "Trimmed stdout of git ARGS in DIR, or nil on failure."
  (with-temp-buffer
    (when (zerop (apply #'call-process "git" nil '(t nil) nil "-C" dir args))
      (string-trim (buffer-string)))))

(defun epkg--read (file)
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (read (current-buffer)))))

(defun epkg--pkg-dir (pkg)
  (expand-file-name (symbol-name pkg) "epkg"))

(defun epkg--lock ()
  "Extant epkg/lock."
  (epkg--read (expand-file-name "lock" "epkg")))

(defun epkg--write-lock (lock)
  (make-directory "epkg" t)
  (with-temp-file (expand-file-name "lock" "epkg")
    (pp (sort lock (lambda (a b) (string< (car a) (car b))))
	(current-buffer))))

(defun epkg--clone (pkg url)
  "Clone URL to epkg/PKG unless present from URL."
  (let ((dir (epkg--pkg-dir pkg)))
    (when (and (file-directory-p dir)
	       (not (equal url (epkg--git dir "remote" "get-url" "origin"))))
      (unless (and (equal "" (epkg--git dir "status" "--porcelain"))
		   (equal "" (epkg--git dir "rev-list" "HEAD" "--branches" "--not" "--remotes")))
	(error "epkg: %s has local work, cannot reclone from %s" dir url))
      (delete-directory dir t))
    (unless (file-directory-p dir)
      (unless (zerop (call-process "git" nil nil nil "clone" "--quiet" url dir))
	(error "epkg: git clone %s failed" url)))
    dir))

(defun epkg--commit (dir rev)
  (or (epkg--git dir "rev-parse" "--verify" "--quiet" (concat rev "^{commit}"))
      (error "epkg: %s lacks %s" dir rev)))

(defun epkg-requires (&rest files)
  "Locally clone each epkg-require in FILES.
Return list of (PKG :url URL :sha1 SHA1), SHA1 being the locked
commit, else the remote's default branch tip."
  (let ((lock (epkg--lock))
	reqs)
    (dolist (file files)
      (with-temp-buffer
	(insert-file-contents file)
	(condition-case nil
	    (while t
	      (setq reqs (epkg--collect-requires (read (current-buffer)) reqs)))
	  (end-of-file))))
    (mapcar (lambda (req)
	      (let* ((url (if (url-type (url-generic-parse-url (cdr req)))
			      (cdr req)
			    (concat "https://" (cdr req))))
		     (dir (epkg--clone (car req) url))
		     (locked (alist-get (car req) lock)))
		(list (car req) :url url
		      :sha1 (epkg--commit dir (if (equal url (plist-get locked :url))
						  (plist-get locked :sha1)
						"refs/remotes/origin/HEAD")))))
	    reqs)))

(defun epkg--latest (pkg dir sha1s)
  (let ((best (car sha1s)))
    (dolist (sha1 (cdr sha1s) best)
      (cond ((epkg--git dir "merge-base" "--is-ancestor" best sha1)
	     (setq best sha1))
	    ((epkg--git dir "merge-base" "--is-ancestor" sha1 best))
	    (t (error "epkg-sync: %s %s and %s diverge" pkg best sha1))))))

(defun epkg-sync (&rest files)
  "Merge all epkg/clone/epkg/lock to epkg/lock.
Checkout each clone accordingly."
  (let* ((lock (epkg--lock))
	 (direct (apply #'epkg-requires files))
	 (entries direct)
	 merged)
    (dolist (entry direct)
      (let ((dir (epkg--pkg-dir (car entry)))
	    (sha1 (plist-get (cdr entry) :sha1)))
	(unless (epkg--git dir "checkout" "--quiet" "--detach" sha1)
	  (error "epkg-sync: git checkout %s in %s failed" sha1 dir))
	(setq entries (append entries (epkg--read (expand-file-name "epkg/lock" dir))))))
    (dolist (entry entries)
      (let ((url (plist-get (cdr entry) :url))
	    (sha1 (plist-get (cdr entry) :sha1))
	    (prev (assq (car entry) merged)))
	(cond ((not prev) (push (list (car entry) url sha1) merged))
	      ((not (equal url (cadr prev)))
	       (error "epkg-sync: %s is both %s and %s" (car entry) (cadr prev) url))
	      (t (cl-pushnew sha1 (cddr prev) :test #'equal)))))
    (epkg--write-lock
     (mapcar
      (lambda (m)
	(let ((dir (epkg--clone (car m) (cadr m)))
	      (locked (alist-get (car m) lock))
	      best)
	  (when (equal (cadr m) (plist-get locked :url))
	    (cl-pushnew (plist-get locked :sha1) (cddr m) :test #'equal))
	  (setq best (epkg--latest (car m) dir (delete-dups
						(mapcar (lambda (sha1) (epkg--commit dir sha1))
							(cddr m)))))
	  (unless (epkg--git dir "checkout" "--quiet" "--detach" best)
	    (error "epkg-sync: git checkout %s in %s failed" best dir))
	  (list (car m) :url (cadr m) :sha1 best)))
      merged))))

(defun epkg-get (pkg rev)
  "Fetch PKG and lock it at REV, the remote default tip if REV is empty.
A branch REV means the remote's branch."
  (let* ((lock (epkg--lock))
	 (dir (epkg--pkg-dir pkg))
	 (url (or (plist-get (alist-get pkg lock) :url)
		  (epkg--git dir "remote" "get-url" "origin")
		  (error "epkg-get: no clone of %s" pkg)))
	 (remote (concat "refs/remotes/origin/" rev)))
    (unless (and (epkg--git dir "fetch" "--quiet" "--tags" "origin")
		 (epkg--git dir "remote" "set-head" "origin" "--auto"))
      (error "epkg-get: git fetch in %s failed" dir))
    (setf (alist-get pkg lock)
	  (list :url url
		:sha1 (epkg--commit dir (cond ((string-empty-p rev) "refs/remotes/origin/HEAD")
					      ((epkg--git dir "rev-parse" "--verify" "--quiet" remote)
					       remote)
					      (t rev)))))
    (epkg--write-lock lock)))

(defun epkg-old-requires ()
  "Non-nil if packages under `epkg-dir' satisfy Package-Requires of `epkg-main'.
Write Package-Requires of `epkg-main' to epkg/old-requires if changed."
  (let ((reqs (package-desc-reqs (epkg-desc)))
	(file (expand-file-name "epkg/old-requires"))
	(package-user-dir (expand-file-name "elpa" (epkg-dir)))
	package-directory-list package-alist)
    (when (or (not (file-exists-p file))
	      (not (equal reqs (with-temp-buffer
				 (insert-file-contents file)
				 (ignore-errors (read (current-buffer)))))))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
	(prin1 reqs (current-buffer))))
    (package-load-all-descriptors)
    (seq-every-p (lambda (req) (package-installed-p (car req) (cadr req)))
		 (package-desc-reqs (epkg-desc)))))

(defun epkg-copy-mk ()
  "Copy bundled epkg.mk into `default-directory'."
  (copy-file (expand-file-name "epkg.mk" (file-name-directory (locate-library "epkg")))
	     (expand-file-name "epkg.mk") t))

(provide 'epkg)

;; Local Variables:
;; no-byte-compile: t
;; no-native-compile: t
;; End:

;;; epkg.el ends here
