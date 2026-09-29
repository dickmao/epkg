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
