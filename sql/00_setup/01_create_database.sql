/*
Creates the EcommerceDW database if it does not already exist.

Rerunning this script is safe: it never drops the database, so existing
tables and load history are kept. Each layer's own scripts rebuild the
tables they own.
*/
USE master;
GO

IF DB_ID(N'EcommerceDW') IS NULL
    CREATE DATABASE EcommerceDW;
GO
