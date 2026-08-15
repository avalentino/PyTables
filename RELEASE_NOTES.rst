========================================
 Release notes for PyTables 3.12 series
========================================

:Author: PyTables Developers
:Contact: pytables-dev@googlegroups.com

.. py:currentmodule:: tables

Changes from 3.11.1 to 3.12.0
=============================

* :meth:`Table.where` (and hence :meth:`Table.read_where`,
  :meth:`Table.get_where_list` and :meth:`Table.append_where`) now treats a
  *start* with no *stop* like a Python slice, i.e. the rows from *start* to
  the last one are considered.  Previously only one row was considered
  (:issue:`797`).


Thanks to:

* Teddy Tennant
