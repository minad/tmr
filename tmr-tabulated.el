;;; tmr-tabulated.el --- Display TMR timers in a tabulated list -*- lexical-binding: t -*-

;; Copyright (C) 2020-2023  Free Software Foundation, Inc.

;; Author: Protesilaos Stavrou <info@protesilaos.com>,
;;         Damien Cassou <damien@cassou.me>,
;;         Daniel Mendler <mail@daniel-mendler.de>
;; Maintainer: TMR Development <~protesilaos/tmr@lists.sr.ht>
;; URL: https://git.sr.ht/~protesilaos/tmr
;; Mailing-List: https://lists.sr.ht/~protesilaos/tmr

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Call `M-x tmr-tabulated-view' to display all tmr timers in a grid,
;; one by line with sortable columns.  Columns show the creation date,
;; the end date, a check mark if the timer is finished and the timer's
;; optional description.
;;
;; Please read the manual for all the technicalities.  Either evaluate
;; (info "(tmr) Top") or visit <https://protesilaos.com/emacs/tmr>.

;;; Code:

(require 'tmr)

;;;###autoload
(defun tmr-tabulated-view ()
  "Open a tabulated list buffer listing tmr timers."
  (interactive)
  (switch-to-buffer (get-buffer-create "*tmr-tabulated-view*"))
  (tmr-tabulated-mode))

(defalias 'tmr-list-timers 'tmr-tabulated-view
  "Alias of `tmr-tabulated-view' command.")

(defun tmr-tabulated--set-entries ()
  "Set the value of `tabulated-list-entries' with timers."
  (setq-local tabulated-list-entries
              (mapcar #'tmr-tabulated--timer-to-entry tmr--timers)))

(defun tmr-tabulated--timer-to-entry (timer)
  "Convert TIMER into an entry suitable for `tabulated-list-entries'."
  (list timer
        (vector (tmr--format-creation-date timer)
                (tmr--format-end-date timer)
                (tmr--format-remaining timer)
                (if (tmr--timer-acknowledgep timer) "✔" "")
                (or (tmr--timer-description timer) ""))))

(defvar-keymap tmr-tabulated-mode-map
  :doc "Keybindings for `tmr-tabulated-mode-map'."
  "k" #'tmr-remove
  "r" #'tmr-remove
  "R" #'tmr-remove-finished
  "+" #'tmr
  "t" #'tmr
  "*" #'tmr-with-details
  "T" #'tmr-with-details
  "c" #'tmr-clone
  "a" #'tmr-toggle-acknowledge
  "e" #'tmr-edit-description
  "s" #'tmr-reschedule)

(defvar-local tmr-tabulated--refresh-timer nil
  "Timer used to refresh tabulated view.")

(defun tmr-tabulated--window-hook ()
  "Setup timer to refresh tabulated view."
  (if (get-buffer-window)
      (unless tmr-tabulated--refresh-timer
        (let* ((timer nil)
               (buf (current-buffer))
               (refresh
                (lambda ()
                  (if (buffer-live-p buf)
                      (with-current-buffer buf
                        (if-let (win (get-buffer-window))
                            (with-selected-window win
                              (let ((end (eobp)))
                                ;; Optimized refreshing
                                (dolist (entry tabulated-list-entries)
                                  (setf (aref (cadr entry) 2) (tmr--format-remaining (car entry))))
                                (tabulated-list-print t)
                                (when end (goto-char (point-max))))
                              ;; HACK: For some reason the hl-line highlighting gets lost here
                              (when (and (bound-and-true-p global-hl-line-mode)
                                         (fboundp 'global-hl-line-highlight))
                                (global-hl-line-highlight))
                              (when (and (bound-and-true-p hl-line-mode)
                                         (fboundp 'hl-line-highlight))
                                (hl-line-highlight)))
                          (cancel-timer timer)
                          (setq tmr-tabulated--refresh-timer nil)))
                    (cancel-timer timer)))))
          (setq timer (run-at-time 1 1 refresh)
                tmr-tabulated--refresh-timer timer)))
    (when tmr-tabulated--refresh-timer
      (cancel-timer tmr-tabulated--refresh-timer)
      (setq tmr-tabulated--refresh-timer nil))))

(defun tmr-tabulated--compare-remaining (a b)
  "Compare remaining time of timers A and B."
  (time-less-p (tmr--timer-end-date (car a))
               (tmr--timer-end-date (car b))))

(define-derived-mode tmr-tabulated-mode tabulated-list-mode "TMR"
  "Major mode to display tmr timers."
  (setq-local tabulated-list-format
              [("Start" 10 t)
               ("End" 10 t)
               ("Remaining" 10 tmr-tabulated--compare-remaining)
               ("Ack" 3 t)
               ("Description" 0 t)])
  (add-hook 'window-configuration-change-hook #'tmr-tabulated--window-hook nil t)
  (add-hook 'tabulated-list-revert-hook #'tmr-tabulated--set-entries nil t)
  (tmr-tabulated--set-entries)
  (tabulated-list-init-header)
  (tabulated-list-print))

(defun tmr-tabulated--timer-at-point ()
  "Return the timer on the current line or nil."
  (and (eq major-mode #'tmr-tabulated-mode) (tabulated-list-get-id)))

(defun tmr-tabulated--refresh ()
  "Refresh *tmr-tabulated-view* buffer if it exists."
  (when-let (buf (get-buffer "*tmr-tabulated-view*"))
    (with-current-buffer buf
      (let ((lines (line-number-at-pos)))
        (revert-buffer)
        (when (and (bobp) (> lines 1))
          (forward-line (1- lines))
          (unless (tabulated-list-get-id)
            (forward-line -1)))))))

(add-hook 'tmr--update-hook #'tmr-tabulated--refresh)
(add-hook 'tmr--read-timer-hook #'tmr-tabulated--timer-at-point)

(make-obsolete 'tmr-tabulated-clone #'tmr-clone "0.4.0")
(make-obsolete 'tmr-tabulated-edit-description #'tmr-edit-description "0.4.0")
(make-obsolete 'tmr-tabulated-reschedule #'tmr-reschedule "0.4.0")

(provide 'tmr-tabulated)
;;; tmr-tabulated.el ends here
