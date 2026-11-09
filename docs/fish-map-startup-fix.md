# Fish Map startup fix

In 0.1.13, the Fishing service used ports 8765–8795, but the embedded browser allowed 8925–8955. This could block the map with WebView status 14.

Both now use the same Stable port constants, 8765–8795. Authentication and save locations are unchanged.

The fix was checked against all ports, malformed origins and Gathering restrictions. A synthetic native check loaded both ends of the allowed range and reopened the map. These checks do not replace installer or update tests.
