;;; epkg.el --- Make-based build tool  -*- lexical-binding: t -*-

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

;;; Commentary

;; We call the git repository utilizing epkg the "client."

(require 'package)
(require 'cl-lib)
(require 'url-parse)

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
    (package--make-autoloads-and-stuff pkg-desc pkg-dir)
    ;; We need a separate, untracked (via git) epkg.installed distinct
    ;; from epkg.lock to prepend the client's commit hash since
    ;; epkg.lock cannot know this before committing itself
    (epkg--write-lock (cons (list (package-desc-name pkg-desc)
				  :url (alist-get :url (package-desc-extras pkg-desc))
				  :sha1 (epkg--sha1 default-directory "HEAD"))
			    (epkg--lock))
		      (expand-file-name "epkg.installed" pkg-dir))))

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

(defun epkg--git (dir &rest args)
  "Trimmed stdout of git ARGS in DIR, or nil on failure."
  (with-temp-buffer
    (when (zerop (apply #'call-process "git" nil '(t nil) nil "-C" (expand-file-name dir) args))
      (string-trim (buffer-string)))))

(defun epkg--read (file)
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (read (current-buffer)))))

(defun epkg--lock ()
  "Extant epkg.lock."
  (epkg--read "epkg.lock"))

(defun epkg--write-lock (lock &optional file)
  (with-temp-file (or file "epkg.lock")
    (pp (sort lock (lambda (a b) (string< (car a) (car b))))
	(current-buffer))))

(defun epkg--clone-require (pkg url)
  "Clone URL to epkg/PKG unless present from URL."
  (let ((dir (expand-file-name (symbol-name pkg) "epkg")))
    (when (and (file-directory-p dir)
	       (not (equal url (epkg--git dir "remote" "get-url" "origin"))))
      (delete-directory dir t))
    (unless (file-directory-p dir)
      (when (or (not (zerop (call-process "git" nil nil nil "clone" "--quiet" url dir)))
		(not (epkg--git dir "checkout" "--quiet" "--detach")))
	(error "epkg: git clone %s failed" url)))
    dir))

(defun epkg--sha1 (dir rev)
  ;; ^{commit} resolves an annotated tag to its commit, not the tag object.
  (or (epkg--git dir "rev-parse" "--verify" "--quiet" (concat rev "^{commit}"))
      (error "epkg: %s lacks %s" dir rev)))

(defun epkg--requires (&rest files)
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
    ;; mapc returns the mapcar
    (mapc (lambda (entry)
	    (let ((dir (expand-file-name (symbol-name (car entry)) "epkg"))
		  (sha1 (plist-get (cdr entry) :sha1)))
	      (unless (epkg--git dir "checkout" "--quiet" "--detach" sha1)
		(error "epkg--requires: git checkout %s in %s failed" sha1 dir))))
	  (mapcar (lambda (req)
		    (let* ((url (if (url-type (url-generic-parse-url (cdr req)))
				    (cdr req)
				  (concat "https://" (cdr req))))
			   (dir (epkg--clone-require (car req) url))
			   (locked (alist-get (car req) lock)))
		      ;; Detached HEAD may be stale; origin/HEAD is unequivocal.
		      (list (car req)
			    :url url
			    :sha1 (epkg--sha1 dir (if (equal url (plist-get locked :url))
						      (plist-get locked :sha1)
						    "origin/HEAD")))))
		  reqs))))

(defun epkg--installed-sha1 (pkg)
  "Self-locked sha1 of PKG's active installation."
  (when-let* ((desc (car (alist-get pkg package-alist))))
    (plist-get (alist-get pkg (epkg--read (expand-file-name
					   "epkg.installed" (package-desc-dir desc))))
	       :sha1)))

(defun epkg--latest (pkg dir sha1s)
  (let ((best (car sha1s)))
    (dolist (sha1 (cdr sha1s) best)
      (cond ((epkg--git dir "merge-base" "--is-ancestor" best sha1)
	     (setq best sha1))
	    ((epkg--git dir "merge-base" "--is-ancestor" sha1 best))
	    (t (error "epkg-requires: %s %s and %s diverge" pkg best sha1))))))

(defun epkg--install-order (pkgs)
  "PKGS ordered so each follows those in its epkg/PKG/epkg.lock."
  (let (order visiting)
    (cl-labels ((visit (pkg)
		  (unless (or (memq pkg order) (memq pkg visiting))
		    (push pkg visiting)
		    (mapc #'visit (mapcar #'car (epkg--read
						 (expand-file-name
						  "epkg.lock"
						  (expand-file-name (symbol-name pkg) "epkg")))))
		    (push pkg order))))
      (mapc #'visit pkgs))
    (nreverse order)))

(defun epkg-requires (&rest elsrc)
  "Merge all epkg/clone/epkg.lock to epkg.lock.
Assume epkg/clone/epkg.lock describes a transitive closure for all of
clone's dependencies, so that we don't need to recursively take
`epkg--requires'."
  (package-load-all-descriptors)
  (let* ((lock (epkg--lock))
	 (requires* (apply #'epkg--requires elsrc))
	 (requires requires*)
	 urls sha1s)
    ;; Cumulate each dependency's epkg.lock
    (dolist (entry requires*)
      (let ((more (epkg--read (expand-file-name
			       "epkg.lock"
			       (expand-file-name (symbol-name (car entry)) "epkg")))))
	(setq requires (append requires more))))
    ;; Build sha1s candidates for each PKG
    (dolist (entry requires)
      ;; (PKG :url URL :sha1 SHA1)
      (let ((pkg (car entry))
	    (url (plist-get (cdr entry) :url)))
	(when-let* ((prev (alist-get (car entry) urls)))
	  (unless (equal url prev)
	    (error "epkg-requires: %s is both %s and %s" pkg prev url)))
	(setf (alist-get pkg urls) url)
	(cl-pushnew (plist-get (cdr entry) :sha1) (alist-get pkg sha1s) :test #'equal)))
    ;; Latest of sha1s
    (let ((entries
	   (mapcar
	    (lambda (u)
	      (cl-destructuring-bind (pkg . url) u
		(let ((dir (epkg--clone-require pkg url))
		      (locked (alist-get pkg lock))
		      (candidates (alist-get pkg sha1s))
		      best)
		  ;; CANDIDATES don't yet reflect extant epkg.lock; tack
		  ;; them on here
		  (when (equal url (plist-get locked :url))
		    (cl-pushnew (plist-get locked :sha1) candidates :test #'equal))
		  (setq best (epkg--latest pkg dir (delete-dups
						    (mapcar (lambda (sha1) (epkg--sha1 dir sha1))
							    candidates))))
		  (unless (epkg--git dir "checkout" "--quiet" "--detach" best)
		    (error "epkg-requires: git checkout %s in %s failed" best dir))
		  (list pkg :url url :sha1 best))))
	    urls)))
      ;; ENTRIES is the transitive closure, so `-o epkg-requires` on
      ;; each dependency avoids repeat work.
      (dolist (pkg (epkg--install-order (mapcar #'car entries)))
	(let ((dir (expand-file-name (symbol-name pkg) "epkg"))
	      (best (plist-get (alist-get pkg entries) :sha1)))
	  (unless (when-let* ((installed (epkg--installed-sha1 pkg)))
		    (equal installed
			   (or (ignore-errors (epkg--latest pkg dir (list installed best)))
			       (progn (epkg--git dir "fetch" "--quiet" "--tags" "origin")
				      (epkg--latest pkg dir (list installed best))))))
	    (with-temp-buffer
	      (let ((status (call-process
			     "make" nil t nil "-C" dir "install" "-o" "epkg-requires"
			     (format "EPKG_INSTALL='--init-directory=%s'" user-emacs-directory))))
		(princ (buffer-string))
		(unless (zerop status)
		  (error "epkg-requires: make install in %s failed" dir)))))))
      (epkg--write-lock entries))))

(defun epkg-get (pkg rev)
  "Fetch PKG and lock it at REV.
A branch REV means the remote's branch."
  (let* ((lock (epkg--lock))
	 (dir (expand-file-name (symbol-name pkg) "epkg"))
	 (url (or (plist-get (alist-get pkg lock) :url)
		  (epkg--git dir "remote" "get-url" "origin")
		  (error "epkg-get: no clone of %s" pkg)))
	 (remote (concat "refs/remotes/origin/" rev)))
    (unless (epkg--git dir "fetch" "--quiet" "--tags" "origin")
      (error "epkg-get: git fetch in %s failed" dir))
    (let ((sha1 (epkg--sha1 dir (if (epkg--git dir "rev-parse" "--verify" "--quiet" remote)
				    remote
				  rev))))
      (unless (epkg--git dir "checkout" "--quiet" "--detach" sha1)
	(error "epkg-get: git checkout %s in %s failed" sha1 dir))
      (setf (alist-get pkg lock) (list :url url :sha1 sha1)))
    (package-initialize :no-activate)
    (apply #'package-delete (alist-get pkg package-alist))
    (epkg--write-lock lock)))

(defun epkg-install ()
  (package-initialize)
  (ignore-errors (apply #'package-delete (alist-get (package-desc-name (epkg-desc)) package-alist)))
  (package-refresh-contents nil)
  (package-install-file (expand-file-name (concat (epkg-name-version) ".tar")
					  (epkg-dir))))

(defun epkg-copy-mk ()
  "Copy bundled epkg.mk into `default-directory'."
  (copy-file (expand-file-name "epkg.mk" (file-name-directory (locate-library "epkg")))
	     (expand-file-name "epkg.mk") t))

(defun epkg-package-requires-met ()
  "Non-nil if packages under `epkg-dir' satisfy Package-Requires of `epkg-main'."
  (let (package-directory-list package-alist)
    (package-load-all-descriptors)
    (seq-every-p (lambda (req) (package-installed-p (car req) (cadr req)))
		 (package-desc-reqs (epkg-desc)))))

(provide 'epkg)

;; Local Variables:
;; no-byte-compile: t
;; no-native-compile: t
;; End:

;;; epkg.el ends here
