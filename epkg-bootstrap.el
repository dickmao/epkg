;;; epkg-bootstrap.el --- buzz buzz -*- lexical-binding:t -*-

(require 'package)

(defsubst epkg-bootstrap-where ()
  (directory-file-name (expand-file-name (locate-dominating-file
					  default-directory "epkg.el"))))

(defsubst epkg-bootstrap-desc ()
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "epkg.el" (epkg-bootstrap-where)))
    (package-buffer-info)))

(defun epkg-bootstrap-name ()
  (concat "epkg-" (package-version-join (package-desc-version (epkg-bootstrap-desc)))))

(defun epkg-bootstrap-inception ()
  "To get a -pkg.el file, you need to run `package-unpack'.
To run `package-unpack', you need a -pkg.el."
  (let ((pkg-desc (epkg-bootstrap-desc))
	(pkg-dir (expand-file-name (epkg-bootstrap-name)
				   (epkg-bootstrap-where))))
    (ignore-errors (delete-directory pkg-dir t))
    (make-directory pkg-dir t)
    (copy-file (expand-file-name "epkg.el" (epkg-bootstrap-where))
	       (file-name-as-directory pkg-dir))
    (package--make-autoloads-and-stuff pkg-desc pkg-dir)))
