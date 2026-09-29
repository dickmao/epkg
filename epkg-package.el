;;; epkg-package.el --- buzz buzz -*- lexical-binding:t -*-

(require 'package)
(require 'project)

(defsubst epkg-package-where ()
  (directory-file-name (expand-file-name (project-root (project-current)))))

(defsubst epkg-package-desc ()
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "epkg.el" (epkg-package-where)))
    (package-buffer-info)))

(defun epkg-package-name ()
  (concat "epkg-" (package-version-join (package-desc-version (epkg-package-desc)))))

(defun epkg-package-inception ()
  "To get a -pkg.el file, you need to run `package-unpack'.
To run `package-unpack', you need a -pkg.el."
  (let ((pkg-desc (epkg-package-desc))
	(pkg-dir (expand-file-name (epkg-package-name)
				   (epkg-package-where))))
    (ignore-errors (delete-directory pkg-dir t))
    (make-directory pkg-dir t)
    (dolist (el (split-string "epkg.el"))
      (copy-file (expand-file-name el (epkg-package-where))
		 (expand-file-name el pkg-dir)))
    (package--make-autoloads-and-stuff pkg-desc pkg-dir)))
