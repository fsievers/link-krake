CREATE TABLE Domains (
	id SERIAL PRIMARY KEY,
	domain TEXT
);
CREATE TABLE URLs (
	id SERIAL PRIMARY KEY,
	url TEXT,
	scanned NUMERIC,
	domain NUMERIC,
	last_scan TIMESTAMP,
	errors NUMERIC,
	last_error TIMESTAMP
);
INSERT INTO URLs (url,scanned) VALUES('http://www.ietf.org/rfc.html',0);
CREATE UNIQUE INDEX domain ON Domains(domain);
CREATE UNIQUE INDEX url ON URLs(url);
