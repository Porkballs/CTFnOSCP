# BloodHound Cypher Query Cheatsheet

A reference collection of Neo4j Cypher queries for BloodHound, split into GUI/Graph queries (return paths/nodes for visualization) and Console queries (return tabular data).

> **Note:** Many queries use placeholders like `DOMAIN.GR`, `TESTLAB.LOCAL`, or `DOMAIN ADMINS@DOMAIN.GR`. Replace these with your target domain. Some queries reference legacy properties (e.g. `highvalue`); in BloodHound CE these may map to `system_tags`/Tier Zero, so adjust as needed.

---

## GUI / Graph Queries

### Owned Users & Computers

**Find all edges any owned user has on a computer**

```cypher
MATCH p=shortestPath((m:User)-[r]->(b:Computer)) WHERE m.owned RETURN p
```

### Kerberoasting / SPNs

**Find all users with an SPN (Kerberoastable users)**

```cypher
MATCH (n:User) WHERE n.hasspn=true
RETURN n
```

**Kerberoastable users with passwords last set > 5 years ago**

```cypher
MATCH (u:User) WHERE u.hasspn=true AND u.pwdlastset < (datetime().epochseconds - (1825 * 86400)) AND NOT u.pwdlastset IN [-1.0, 0.0]
RETURN u.name, u.pwdlastset ORDER BY u.pwdlastset
```

**Find SPNs with keywords (swap `SQL` for whatever you want)**

```cypher
MATCH (u:User) WHERE ANY (x IN u.serviceprincipalnames WHERE toUpper(x) CONTAINS 'SQL') RETURN u
```

**Kerberoastable users with a path to Domain Admin**

```cypher
MATCH (u:User {hasspn:true})
MATCH (g:Group) WHERE g.name CONTAINS 'DOMAIN ADMINS'
MATCH p = shortestPath((u)-[*1..]->(g)) RETURN p
```

### AS-REP Roasting

**Find users that don't require Kerberos pre-authentication**

```cypher
MATCH (u:User {dontreqpreauth: true}) RETURN u
```

### RDP Access

**Find workstations a user can RDP into**

```cypher
MATCH p=(g:Group)-[:CanRDP]->(c:Computer) WHERE g.objectid ENDS WITH '-513' AND NOT c.operatingsystem CONTAINS 'Server' RETURN p
```

**Find servers a user can RDP into**

```cypher
MATCH p=(g:Group)-[:CanRDP]->(c:Computer) WHERE g.objectid ENDS WITH '-513' AND c.operatingsystem CONTAINS 'Server' RETURN p
```

### Sessions

**Domain Admin sessions not on a certain group (e.g. domain controllers)**

```cypher
OPTIONAL MATCH (c:Computer)-[:MemberOf]->(t:Group) WHERE NOT t.name = 'DOMAIN CONTROLLERS@TESTLAB.LOCAL'
WITH c AS NonDC
MATCH p=(NonDC)-[:HasSession]->(n:User)-[:MemberOf]->(g:Group {name:"DOMAIN ADMINS@TESTLAB.LOCAL"})
RETURN DISTINCT(n.name) AS Username, COUNT(DISTINCT(NonDC)) AS Connexions ORDER BY COUNT(DISTINCT(NonDC)) DESC
```

**Find all sessions any user in a specific domain has**

```cypher
MATCH p=(m:Computer)-[r:HasSession]->(n:User {domain: "TEST.LOCAL"}) RETURN p
```

### Delegation

**Find all computers with Unconstrained Delegation**

```cypher
MATCH (c:Computer {unconstraineddelegation:true}) RETURN c
```

**Display a specific user with constrained delegation and their targets**

```cypher
MATCH (u:User {name:'USER@DOMAIN.GR'}),(c:Computer),p=((u)-[r:AllowedToDelegate]->(c)) RETURN p
```

### Operating Systems

**Find unsupported OSs**

```cypher
MATCH (H:Computer) WHERE H.operatingsystem =~ '.*(2000|2003|2008|xp|vista|7|me)*.' RETURN H
```

### Logon & Password Times

**Find users that logged in within the last 90 days** (change `90` to your threshold)

```cypher
MATCH (u:User) WHERE u.lastlogon < (datetime().epochseconds - (90 * 86400)) AND NOT u.lastlogon IN [-1.0, 0.0] RETURN u
```

**Find users with passwords last set within the last 90 days** (change `90` to your threshold)

```cypher
MATCH (u:User) WHERE u.pwdlastset < (datetime().epochseconds - (90 * 86400)) AND NOT u.pwdlastset IN [-1.0, 0.0] RETURN u
```

### GPOs

**View all GPOs**

```cypher
MATCH (n:GPO) RETURN n
```

**View all GPOs that contain a keyword**

```cypher
MATCH (n:GPO) WHERE n.name CONTAINS "SERVER" RETURN n
```

### Groups

**View all groups that contain the word 'admin'**

```cypher
MATCH (n:Group) WHERE n.name CONTAINS "ADMIN" RETURN n
```

**Find a group with keywords (e.g. SQL ADMINS or SQL 2017 ADMINS)**

```cypher
MATCH (g:Group) WHERE g.name =~ '(?i).*SQL.*ADMIN.*' RETURN g
```

**Show all high value target groups**

```cypher
MATCH p=(n:User)-[r:MemberOf*1..]->(m:Group {highvalue:true}) RETURN p
```

### Shortest Paths to Domain Admins

**From computers**

```cypher
MATCH (n:Computer),(m:Group {name:'DOMAIN ADMINS@DOMAIN.GR'}),
p=shortestPath((n)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct*1..]->(m)) RETURN p
```

**From computers, excluding potential DCs (based on ldap/ and GC/ SPNs)**

```cypher
WITH '(?i)ldap/.*' AS regex_one
WITH '(?i)gc/.*' AS regex_two
MATCH (n:Computer) WHERE NOT ANY(item IN n.serviceprincipalnames WHERE item =~ regex_two OR item =~ regex_two)
MATCH (m:Group {name:"DOMAIN ADMINS@DOMAIN.GR"}),
p=shortestPath((n)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct*1..]->(m)) RETURN p
```

**From all domain groups**

```cypher
MATCH (n:Group),(m:Group {name:'DOMAIN ADMINS@DOMAIN.GR'}),
p=shortestPath((n)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct*1..]->(m)) RETURN p
```

**From non-privileged groups (`admincount=false`)**

```cypher
MATCH (n:Group {admincount:false}),(m:Group {name:'DOMAIN ADMINS@DOMAIN.GR'}),
p=shortestPath((n)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct*1..]->(m)) RETURN p
```

**From the Domain Users group**

```cypher
MATCH (g:Group) WHERE g.name =~ 'DOMAIN USERS@.*'
MATCH (g1:Group) WHERE g1.name =~ 'DOMAIN ADMINS@.*'
OPTIONAL MATCH p=shortestPath((g)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct|SQLAdmin*1..]->(g1)) RETURN p
```

**From non-privileged users (`admincount=false`)**

```cypher
MATCH (n:User {admincount:false}),(m:Group {name:'DOMAIN ADMINS@DOMAIN.GR'}),
p=shortestPath((n)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct*1..]->(m)) RETURN p
```

### Domain Users Privileges / ACEs

**Find interesting privileges/ACEs configured to the Domain Users group**

```cypher
MATCH (m:Group) WHERE m.name =~ 'DOMAIN USERS@.*'
MATCH p=(m)-[r:Owns|WriteDacl|GenericAll|WriteOwner|ExecuteDCOM|GenericWrite|AllowedToDelegate|ForceChangePassword]->(n:Computer) RETURN p
```

### ACL Abuse

**All edges a specific user has against all nodes** (HasSession excluded — it points computer→user)

```cypher
MATCH (n:User) WHERE n.name =~ 'HELPDESK@DOMAIN.GR'
MATCH (m) WHERE NOT m.name = n.name
MATCH p=allShortestPaths((n)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct|SQLAdmin*1..]->(m)) RETURN p
```

**All edges any unprivileged user (`admincount:False`) has against all nodes**

```cypher
MATCH (n:User {admincount:False})
MATCH (m) WHERE NOT m.name = n.name
MATCH p=allShortestPaths((n)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct|SQLAdmin*1..]->(m)) RETURN p
```

**ACL abuse edges unprivileged users have against other users**

```cypher
MATCH (n:User {admincount:False})
MATCH (m:User) WHERE NOT m.name = n.name
MATCH p=allShortestPaths((n)-[r:AllExtendedRights|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner*1..]->(m)) RETURN p
```

**ACL abuse edges unprivileged users have against computers**

```cypher
MATCH (n:User {admincount:False})
MATCH p=allShortestPaths((n)-[r:AllExtendedRights|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|AdminTo|CanRDP|ExecuteDCOM|ForceChangePassword*1..]->(m:Computer)) RETURN p
```

**Find if unprivileged users can add members into groups**

```cypher
MATCH (n:User {admincount:False})
MATCH p=allShortestPaths((n)-[r:AddMember*1..]->(m:Group)) RETURN p
```

### Domain User Privileges Against Computers

**Find active user sessions on all domain computers**

```cypher
MATCH p1=shortestPath(((u1:User)-[r1:MemberOf*1..]->(g1:Group)))
MATCH p2=(c:Computer)-[*1]->(u1) RETURN p2
```

**All privileges (edges) of domain users against domain computers** (HasSession excluded)

```cypher
MATCH p1=shortestPath(((u1:User)-[r1:MemberOf*1..]->(g1:Group)))
MATCH p2=(u1)-[*1]->(c:Computer) RETURN p2
```

**Only AdminTo privileges of domain users against domain computers**

```cypher
MATCH p1=shortestPath(((u1:User)-[r1:MemberOf*1..]->(g1:Group)))
MATCH p2=(u1)-[:AdminTo*1..]->(c:Computer) RETURN p2
```

**Only CanRDP privileges of domain users against domain computers**

```cypher
MATCH p1=shortestPath(((u1:User)-[r1:MemberOf*1..]->(g1:Group)))
MATCH p2=(u1)-[:CanRDP*1..]->(c:Computer) RETURN p2
```

---

## Console Queries

These return tabular output rather than graph paths — useful in the Neo4j console or BloodHound's raw query / Cypher tab.

### RDP, Password Reset & Local Admin

**Find what groups can RDP**

```cypher
MATCH p=(m:Group)-[r:CanRDP]->(n:Computer) RETURN m.name, n.name ORDER BY m.name
```

**Find what groups can reset passwords**

```cypher
MATCH p=(m:Group)-[r:ForceChangePassword]->(n:User) RETURN m.name, n.name ORDER BY m.name
```

**Find what groups have local admin rights**

```cypher
MATCH p=(m:Group)-[r:AdminTo]->(n:Computer) RETURN m.name, n.name ORDER BY m.name
```

**Find what users have local admin rights**

```cypher
MATCH p=(m:User)-[r:AdminTo]->(n:Computer) RETURN m.name, n.name ORDER BY m.name
```

### Owned Users

**List the groups of all owned users**

```cypher
MATCH (m:User) WHERE m.owned=TRUE WITH m MATCH p=(m)-[:MemberOf*1..]->(n:Group) RETURN m.name, n.name ORDER BY m.name
```

**List the unique groups of all owned users**

```cypher
MATCH (m:User) WHERE m.owned=TRUE WITH m MATCH (m)-[r:MemberOf*1..]->(n:Group) RETURN DISTINCT(n.name)
```

### Domain Admin Sessions

**All active Domain Admin sessions**

```cypher
MATCH (n:User)-[:MemberOf*1..]->(g:Group) WHERE g.objectid ENDS WITH '-512'
MATCH p = (c:Computer)-[:HasSession]->(n) RETURN p
```

**All active sessions a member of a group has**

```cypher
MATCH (n:User)-[:MemberOf*1..]->(g:Group {name:'DOMAIN ADMINS@TESTLAB.LOCAL'})
MATCH p = (c:Computer)-[:HasSession]->(n) RETURN p
```

### Cross-Domain / Cross-Forest

**Can an object from domain 'A' do anything to an object in domain 'B'**

```cypher
MATCH (n {domain:"TEST.LOCAL"})-[r]->(m {domain:"LAB.LOCAL"})
RETURN LABELS(n)[0],n.name,TYPE(r),LABELS(m)[0],m.name
```

**Find all connections to a different domain/forest**

```cypher
MATCH (n)-[r]->(m) WHERE NOT n.domain = m.domain
RETURN LABELS(n)[0],n.name,TYPE(r),LABELS(m)[0],m.name
```

### Kerberoasting (Console)

**Kerberoastable users with passwords last set > 5 years ago**

```cypher
MATCH (u:User) WHERE u.hasspn=true AND u.pwdlastset < (datetime().epochseconds - (1825 * 86400)) AND NOT u.pwdlastset IN [-1.0, 0.0] RETURN u.name, u.pwdlastset ORDER BY u.pwdlastset
```

> Note: the original cheatsheet listed this with a malformed `WHERE n.hasspn=true AND WHERE u.pwdlastset...` clause; corrected above.

**Kerberoastable users with most privileges**

```cypher
MATCH (u:User {hasspn:true})
OPTIONAL MATCH (u)-[:AdminTo]->(c1:Computer)
OPTIONAL MATCH (u)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2:Computer)
WITH u, COLLECT(c1) + COLLECT(c2) AS tempVar
UNWIND tempVar AS comps
RETURN u.name, COUNT(DISTINCT(comps)) ORDER BY COUNT(DISTINCT(comps)) DESC
```

**Find every user that doesn't require Kerberos pre-authentication**

```cypher
MATCH (u:User {dontreqpreauth: true}) RETURN u.name
```

**Find Kerberoastable users who are members of high value groups**

```cypher
MATCH (u:User)-[r:MemberOf*1..]->(g:Group) WHERE g.highvalue=true AND u.hasspn=true RETURN u.name AS USER
```

**Find Kerberoastable users and where they are AdminTo**

```cypher
OPTIONAL MATCH (u1:User) WHERE u1.hasspn=true
OPTIONAL MATCH (u1)-[r:AdminTo]->(c:Computer)
RETURN u1.name AS user_with_spn, c.name AS local_admin_to
```

### Logon & Password Times (Console)

**Find users that logged in within the last 90 days**

```cypher
MATCH (u:User) WHERE u.lastlogon < (datetime().epochseconds - (90 * 86400)) AND NOT u.lastlogon IN [-1.0, 0.0] RETURN u.name, u.lastlogon ORDER BY u.lastlogon
```

**Find users with passwords last set within the last 90 days**

```cypher
MATCH (u:User) WHERE u.pwdlastset < (datetime().epochseconds - (90 * 86400)) AND NOT u.pwdlastset IN [-1.0, 0.0] RETURN u.name, u.pwdlastset ORDER BY u.pwdlastset
```

**List users and their login + pwd last set times in human-readable format**

```cypher
MATCH (n:User) WHERE n.enabled = TRUE
RETURN n.name, datetime({epochSeconds: toInteger(n.pwdlastset)}), datetime({epochSeconds: toInteger(n.lastlogon)}) ORDER BY n.pwdlastset
```

**Find users that have never logged on and account is still active**

```cypher
MATCH (n:User) WHERE n.lastlogontimestamp=-1.0 AND n.enabled=TRUE RETURN n.name ORDER BY n.name
```

**Adjust query to local timezone** (change timezone parameter)

```cypher
MATCH (u:User) WHERE NOT u.lastlogon IN [-1.0, 0.0]
RETURN u.name, datetime({epochSeconds:toInteger(u.lastlogon), timezone: '+10:00'}) AS LastLogon
```

### Delegation (Console)

**Find constrained delegation**

```cypher
MATCH (u:User)-[:AllowedToDelegate]->(c:Computer) RETURN u.name, COUNT(c) ORDER BY COUNT(c) DESC
```

**Find all users trusted to perform constrained delegation** (ordered by computer count)

```cypher
MATCH (u:User)-[:AllowedToDelegate]->(c:Computer) RETURN u.name, COUNT(c) ORDER BY COUNT(c) DESC
```

**Find users with constrained delegation permissions and their targets**

```cypher
MATCH (u:User) WHERE u.allowedtodelegate IS NOT NULL RETURN u.name, u.allowedtodelegate
```

**Find users with constrained delegation — full context** (targets, impersonatable privileged users, active sessions, shortest paths)

```cypher
OPTIONAL MATCH (u:User {sensitive:false, admincount:true}) WITH u.name AS POSSIBLE_TARGETS
OPTIONAL MATCH (n:User) WHERE n.allowedtodelegate IS NOT NULL WITH n AS USER_WITH_DELEG, n.allowedtodelegate AS DELEGATE_TO, POSSIBLE_TARGETS
OPTIONAL MATCH (c:Computer)-[:HasSession]->(USER_WITH_DELEG) WITH USER_WITH_DELEG, DELEGATE_TO, POSSIBLE_TARGETS, c.name AS USER_WITH_DELEG_HAS_SESSION_TO
OPTIONAL MATCH p=shortestPath((o)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct*1..]->(USER_WITH_DELEG)) WHERE NOT o=USER_WITH_DELEG
WITH USER_WITH_DELEG, DELEGATE_TO, POSSIBLE_TARGETS, USER_WITH_DELEG_HAS_SESSION_TO, p
RETURN USER_WITH_DELEG.name AS USER_WITH_DELEG, DELEGATE_TO, COLLECT(DISTINCT(USER_WITH_DELEG_HAS_SESSION_TO)) AS USER_WITH_DELEG_HAS_SESSION_TO, COLLECT(DISTINCT(POSSIBLE_TARGETS)) AS PRIVILEGED_USERS_TO_IMPERSONATE, COUNT(DISTINCT(p)) AS PATHS_TO_USER_WITH_DELEG
```

**Find computers with constrained delegation permissions and their targets**

```cypher
MATCH (c:Computer) WHERE c.allowedtodelegate IS NOT NULL RETURN c.name, c.allowedtodelegate
```

**Find computers with constrained delegation — full context** (targets, impersonatable privileged users, local admins, shortest paths)

```cypher
OPTIONAL MATCH (u:User {sensitive:false, admincount:true}) WITH u.name AS POSSIBLE_TARGETS
OPTIONAL MATCH (n:Computer) WHERE n.allowedtodelegate IS NOT NULL WITH n AS COMPUTERS_WITH_DELEG, n.allowedtodelegate AS DELEGATE_TO, POSSIBLE_TARGETS
OPTIONAL MATCH (u1:User)-[:AdminTo]->(COMPUTERS_WITH_DELEG) WITH u1 AS DIRECT_ADMINS, POSSIBLE_TARGETS, COMPUTERS_WITH_DELEG, DELEGATE_TO
OPTIONAL MATCH (u2:User)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(COMPUTERS_WITH_DELEG) WITH COLLECT(DIRECT_ADMINS) + COLLECT(u2) AS TempVar, COMPUTERS_WITH_DELEG, DELEGATE_TO, POSSIBLE_TARGETS
UNWIND TempVar AS LOCAL_ADMINS
OPTIONAL MATCH p=shortestPath((o)-[r:MemberOf|HasSession|AdminTo|AllExtendedRights|AddMember|ForceChangePassword|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|CanRDP|ExecuteDCOM|AllowedToDelegate|ReadLAPSPassword|Contains|GpLink|AddAllowedToAct|AllowedToAct*1..]->(COMPUTERS_WITH_DELEG)) WHERE NOT o=COMPUTERS_WITH_DELEG
WITH COMPUTERS_WITH_DELEG, DELEGATE_TO, POSSIBLE_TARGETS, p, LOCAL_ADMINS
RETURN COMPUTERS_WITH_DELEG.name AS COMPUTERS_WITH_DELG, LOCAL_ADMINS.name AS LOCAL_ADMINS_TO_COMPUTERS_WITH_DELG, DELEGATE_TO, COLLECT(DISTINCT(POSSIBLE_TARGETS)) AS PRIVILEGED_USERS_TO_IMPERSONATE, COUNT(DISTINCT(p)) AS PATHS_TO_USER_WITH_DELEG
```

### OUs

**View OUs based on member count**

```cypher
MATCH (o:OU)-[:Contains]->(c:Computer) RETURN o.name, o.guid, COUNT(c) ORDER BY COUNT(c) DESC
```

**Return each OU that has a Windows Server in it**

```cypher
MATCH (o:OU)-[:Contains]->(c:Computer) WHERE toUpper(c.operatingsystem) STARTS WITH "WINDOWS SERVER" RETURN o.name
```

**Show all sessions from users in the OU with a given GUID**

```cypher
MATCH p=(o:OU {guid:'045939B4-3FA8-4735-YU15-7D61CFOU6500'})-[r:Contains*1..]->(u:User)
MATCH (c:Computer)-[rel:HasSession]->(u) RETURN u.name, c.name
```

### Unconstrained Delegation (non-DC)

**Find computers with unconstrained delegation that AREN'T domain controllers**

```cypher
MATCH (c1:Computer)-[:MemberOf*1..]->(g:Group) WHERE g.objectsid ENDS WITH '-516'
WITH COLLECT(c1.name) AS domainControllers
MATCH (c2:Computer {unconstraineddelegation:true}) WHERE NOT c2.name IN domainControllers
RETURN c2.name, c2.operatingsystem ORDER BY c2.name ASC
```

> Note: there are two near-identical variants in the source (one using `objectid`, one using `objectsid`). Use `objectsid` for the DC group `-516` check.

### High Value Targets

**Find number of principals controlling a high-value asset where the principal isn't itself in a high-value group**

```cypher
MATCH (n {highvalue:true})
OPTIONAL MATCH (m1)-[{isacl:true}]->(n) WHERE NOT (m1)-[:MemberOf*1..]->(:Group {highvalue:true})
OPTIONAL MATCH (m2)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(n) WHERE NOT (m2)-[:MemberOf*1..]->(:Group {highvalue:true})
WITH n, COLLECT(m1) + COLLECT(m2) AS tempVar
UNWIND tempVar AS controllers
RETURN n.name, COUNT(DISTINCT(controllers)) ORDER BY COUNT(DISTINCT(controllers)) DESC
```

**List unique users with a path to a high-value group**

```cypher
MATCH (u:User)
MATCH (g:Group {highvalue:true})
MATCH p = shortestPath((u:User)-[r:AddMember|AdminTo|AllExtendedRights|AllowedToDelegate|CanRDP|Contains|ExecuteDCOM|ForceChangePassword|GenericAll|GenericWrite|GpLink|HasSession|MemberOf|Owns|ReadLAPSPassword|TrustedBy|WriteDacl|WriteOwner|GetChanges|GetChangesAll*1..]->(g))
RETURN DISTINCT(u.name) AS USER, u.enabled AS ENABLED, count(p) AS PATHS ORDER BY u.name
```

### Object Properties

**Enumerate all properties of computers**

```cypher
MATCH (n:Computer) RETURN properties(n)
```

**Find users not AdminCount 1, with GenericAll, and no local admin**

```cypher
MATCH (u:User)-[:GenericAll]->(c:Computer) WHERE NOT u.admincount AND NOT (u)-[:AdminTo]->(c) RETURN u.name, c.name
```

**Find every user where the `userpassword` attribute is populated**

```cypher
MATCH (u:User) WHERE NOT u.userpassword IS NULL RETURN u.name, u.userpassword
```

**Find computers with descriptions** (admins sometimes store secrets here)

```cypher
MATCH (c:Computer) WHERE c.description IS NOT NULL RETURN c.name, c.description
```

### Well-Known Group Permissions

**What permissions does Everyone / Authenticated Users / Domain Users / Domain Computers have**

```cypher
MATCH p=(m:Group)-[r:AddMember|AdminTo|AllExtendedRights|AllowedToDelegate|CanRDP|Contains|ExecuteDCOM|ForceChangePassword|GenericAll|GenericWrite|GetChanges|GetChangesAll|HasSession|Owns|ReadLAPSPassword|SQLAdmin|TrustedBy|WriteDACL|WriteOwner|AddAllowedToAct|AllowedToAct]->(t)
WHERE m.objectsid ENDS WITH '-513' OR m.objectsid ENDS WITH '-515' OR m.objectsid ENDS WITH 'S-1-5-11' OR m.objectsid ENDS WITH 'S-1-1-0'
RETURN m.name, TYPE(r), t.name, t.enabled
```

### MSSQL / SPN Searches

**Computers where at least one SPN contains 'MSSQL'**

```cypher
MATCH (c:Computer) WHERE ANY (x IN c.serviceprincipalnames WHERE toUpper(x) CONTAINS 'MSSQL') RETURN c.name, c.serviceprincipalnames ORDER BY c.name ASC
```

### Local Admin Analysis

**Find every computer account with local admin rights on other computers** (count, descending)

```cypher
MATCH (c1:Computer)
OPTIONAL MATCH (c1)-[:AdminTo]->(c2:Computer)
OPTIONAL MATCH (c1)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c3:Computer)
WITH COLLECT(c2) + COLLECT(c3) AS tempVar, c1
UNWIND tempVar AS computers
RETURN c1.name AS COMPUTER, COUNT(DISTINCT(computers)) AS ADMIN_TO_COMPUTERS ORDER BY COUNT(DISTINCT(computers)) DESC
```

**Same, but display the computer names**

```cypher
MATCH (c1:Computer)
OPTIONAL MATCH (c1)-[:AdminTo]->(c2:Computer)
OPTIONAL MATCH (c1)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c3:Computer)
WITH COLLECT(c2) + COLLECT(c3) AS tempVar, c1
UNWIND tempVar AS computers
RETURN c1.name AS COMPUTER, COLLECT(DISTINCT(computers.name)) AS ADMIN_TO_COMPUTERS ORDER BY c1.name
```

**Get computers without admins, alphabetically**

```cypher
MATCH (n)-[r:AdminTo]->(c:Computer) WITH COLLECT(c.name) AS compsWithAdmins
MATCH (c2:Computer) WHERE NOT c2.name IN compsWithAdmins RETURN c2.name ORDER BY c2.name ASC
```

**Count computers that do not have local admins**

```cypher
MATCH (n)-[r:AdminTo]->(c:Computer) WITH COLLECT(c.name) AS compsWithAdmins
MATCH (c2:Computer) WHERE NOT c2.name IN compsWithAdmins RETURN COUNT(c2)
```

**On each computer, who can RDP (enabled users only)**

```cypher
MATCH (c:Computer)
OPTIONAL MATCH (u:User)-[:CanRDP]->(c) WHERE u.enabled=true
OPTIONAL MATCH (u1:User)-[:MemberOf*1..]->(:Group)-[:CanRDP]->(c) WHERE u1.enabled=true
WITH COLLECT(u) + COLLECT(u1) AS tempVar, c
UNWIND tempVar AS users
RETURN c.name AS COMPUTER, COLLECT(DISTINCT(users.name)) AS USERS ORDER BY USERS DESC
```

**On each computer, number of users with admin rights + the users**

```cypher
MATCH (c:Computer)
OPTIONAL MATCH (u1:User)-[:AdminTo]->(c)
OPTIONAL MATCH (u2:User)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c)
WITH COLLECT(u1) + COLLECT(u2) AS TempVar, c
UNWIND TempVar AS Admins
RETURN c.name AS COMPUTER, COUNT(DISTINCT(Admins)) AS ADMIN_COUNT, COLLECT(DISTINCT(Admins.name)) AS USERS ORDER BY ADMIN_COUNT DESC
```

**List all users with local admin and count instances**

```cypher
OPTIONAL MATCH (c1)-[:AdminTo]->(c2:Computer)
OPTIONAL MATCH (c1)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c3:Computer)
WITH COLLECT(c2) + COLLECT(c3) AS tempVar, c1
UNWIND tempVar AS computers
RETURN c1.name, COUNT(DISTINCT(computers)) ORDER BY COUNT(DISTINCT(computers)) DESC
```

### Privileged Groups

**Active Directory group with default privileged rights on users/groups + DC logon (Account Operators)**

```cypher
MATCH (u:User)-[r1:MemberOf*1..]->(g1:Group {name:'ACCOUNT OPERATORS@DOMAIN.GR'}) RETURN u.name
```

**Find which domain groups are admins to what computers**

```cypher
MATCH (g:Group)
OPTIONAL MATCH (g)-[:AdminTo]->(c1:Computer)
OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2:Computer)
WITH g, COLLECT(c1) + COLLECT(c2) AS tempVar
UNWIND tempVar AS computers
RETURN g.name AS GROUP, COLLECT(computers.name) AS AdminRights
```

**Same, excluding Domain Admins and Enterprise Admins**

```cypher
MATCH (g:Group) WHERE NOT (g.name =~ '(?i)domain admins@.*' OR g.name =~ "(?i)enterprise admins@.*")
OPTIONAL MATCH (g)-[:AdminTo]->(c1:Computer)
OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2:Computer)
WITH g, COLLECT(c1) + COLLECT(c2) AS tempVar
UNWIND tempVar AS computers
RETURN g.name AS GROUP, COLLECT(computers.name) AS AdminRights
```

**Same, excluding high-privileged groups (`admincount=true`)**

```cypher
MATCH (g:Group) WHERE g.admincount=false
OPTIONAL MATCH (g)-[:AdminTo]->(c1:Computer)
OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2:Computer)
WITH g, COLLECT(c1) + COLLECT(c2) AS tempVar
UNWIND tempVar AS computers
RETURN g.name AS GROUP, COLLECT(computers.name) AS AdminRights
```

**Find the most privileged groups (admin to computers, nested calculated)**

```cypher
MATCH (g:Group)
OPTIONAL MATCH (g)-[:AdminTo]->(c1:Computer)
OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2:Computer)
WITH g, COLLECT(c1) + COLLECT(c2) AS tempVar
UNWIND tempVar AS computers
RETURN g.name AS GroupName, COUNT(DISTINCT(computers)) AS AdminRightCount ORDER BY AdminRightCount DESC
```

**Find groups with most local admins (explicit + derivative/unrolled)**

```cypher
MATCH (g:Group) WITH g
OPTIONAL MATCH (g)-[r:AdminTo]->(c1:Computer) WITH g, COUNT(c1) AS explicitAdmins
OPTIONAL MATCH (g)-[r:MemberOf*1..]->(a:Group)-[r2:AdminTo]->(c2:Computer)
WITH g, explicitAdmins, COUNT(DISTINCT(c2)) AS unrolledAdmins
RETURN g.name, explicitAdmins, unrolledAdmins, explicitAdmins + unrolledAdmins AS totalAdmins ORDER BY totalAdmins DESC
```

### GPO Abuse

**Find if any domain user has interesting permissions against a GPO**

```cypher
MATCH p=(u:User)-[r:AllExtendedRights|GenericAll|GenericWrite|Owns|WriteDacl|WriteOwner|GpLink*1..]->(g:GPO) RETURN p LIMIT 25
```

### Path Percentages & Statistics

**Percentage of computers with a path to Domain Admins**

```cypher
MATCH (totalComputers:Computer {domain:'DOMAIN.GR'})
MATCH p=shortestPath((ComputersWithPath:Computer {domain:'DOMAIN.GR'})-[r*1..]->(g:Group {name:'DOMAIN ADMINS@DOMAIN.GR'}))
WITH COUNT(DISTINCT(totalComputers)) AS totalComputers, COUNT(DISTINCT(ComputersWithPath)) AS ComputersWithPath
RETURN 100.0 * ComputersWithPath / totalComputers AS percentComputersToDA
```

**Percentage of non-privileged groups (`admincount:false`) with path to Domain Admins**

```cypher
MATCH (totalGroups:Group {admincount:false})
MATCH p=shortestPath((GroupsWithPath:Group {admincount:false})-[r*1..]->(g:Group {name:'DOMAIN ADMINS@DOMAIN.GR'}))
WITH COUNT(DISTINCT(totalGroups)) AS totalGroups, COUNT(DISTINCT(GroupsWithPath)) AS GroupsWithPath
RETURN 100.0 * GroupsWithPath / totalGroups AS percentGroupsToDA
```

**Percentage of users with a path to Domain Admins**

```cypher
MATCH (totalUsers:User {domain:'DOMAIN.GR'})
MATCH p=shortestPath((UsersWithPath:User {domain:'DOMAIN.GR'})-[r*1..]->(g:Group {name:'DOMAIN ADMINS@DOMAIN.GR'}))
WITH COUNT(DISTINCT(totalUsers)) AS totalUsers, COUNT(DISTINCT(UsersWithPath)) AS UsersWithPath
RETURN 100.0 * UsersWithPath / totalUsers AS percentUsersToDA
```

**Percentage of enabled users with a path to high-value groups**

```cypher
MATCH (u:User {domain:'DOMAIN.GR',enabled:True})
MATCH (g:Group {domain:'DOMAIN.GR'}) WHERE g.highvalue = True
WITH g, COUNT(u) AS userCount
MATCH p = shortestPath((u:User {domain:'DOMAIN.GR',enabled:True})-[*1..]->(g))
RETURN 100.0 * COUNT(distinct u) / userCount
```

### Admin Counts per User

**Count computers where each domain user has direct admin privileges**

```cypher
MATCH (u:User)-[:AdminTo]->(c:Computer) RETURN count(DISTINCT(c.name)) AS COMPUTER, u.name AS USER ORDER BY count(DISTINCT(c.name)) DESC
```

**Count computers where each domain user has derivative admin privileges**

```cypher
MATCH (u:User)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c:Computer) RETURN count(DISTINCT(c.name)) AS COMPUTER, u.name AS USER ORDER BY u.name
```

**Display computer names where each domain user has derivative admin privileges**

```cypher
MATCH (u:User)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c:Computer) RETURN DISTINCT(c.name) AS COMPUTER, u.name AS USER ORDER BY u.name
```

### Sessions per User

**Find active sessions a specific domain user has on all domain computers**

```cypher
MATCH p1=shortestPath(((u1:User {name:'USER@DOMAIN.GR'})-[r1:MemberOf*1..]->(g1:Group)))
MATCH (c:Computer)-[r:HasSession*1..]->(u1)
RETURN DISTINCT(u1.name) AS users, c.name AS computers ORDER BY computers
```

### Sensitive / Unconstrained Delegation Attacks

**Find users NOT 'Sensitive and Cannot Be Delegated', with admin access, and sessions on Unconstrained Delegation servers** (by NotMedic)

```cypher
MATCH (u:User {sensitive:false})-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c1:Computer)
WITH u, c1
MATCH (c2:Computer {unconstraineddelegation:true})-[:HasSession]->(u)
RETURN u.name AS user, COLLECT(DISTINCT(c1.name)) AS AdminTo, COLLECT(DISTINCT(c2.name)) AS TicketLocation ORDER BY user ASC
```

### Misc / Group Membership

**Find all users part of the VPN group**

```cypher
MATCH (u:User)-[:MemberOf]->(g:Group) WHERE g.name CONTAINS "VPN" RETURN u.name, g.name
```

---

## Tiering & Tagging Queries

These create custom properties to support an AD tiering model. Several are heavy queries — run with care on large datasets.

**Create a property on users that have an actual path to anything high-value** (heavy — can take hours on a large dataset)

```cypher
MATCH (u:User)
MATCH (g:Group {highvalue: true})
MATCH p = shortestPath((u:User)-[r:AddMember|AdminTo|AllExtendedRights|AllowedToDelegate|CanRDP|Contains|ExecuteDCOM|ForceChangePassword|GenericAll|GenericWrite|GetChangesAll|GpLink|HasSession|MemberOf|Owns|ReadLAPSPassword|SQLAdmin|TrustedBy|WriteDacl|WriteOwner|AddAllowedToAct|AllowedToAct*1..]->(g))
SET u.has_path_to_da = true
```

**Which 'user with path to high-value' has the most sessions**

```cypher
MATCH (c:Computer)-[rel:HasSession]->(u:User {has_path_to_da: true})
WITH COLLECT(c) AS tempVar, u
UNWIND tempVar AS sessions
WITH u, COUNT(DISTINCT(sessions)) AS sessionCount
RETURN u.name, u.displayname, sessionCount ORDER BY sessionCount DESC
```

**Create a property for Tier 1 Users (regex)**

```cypher
MATCH (u:User) WHERE u.name =~ 'internal_naming_convention[0-9]{2,5}@EXAMPLE.LOCAL' SET u.tier_1_user = true
```

**Create a property for Tier 1 Computers (group membership)**

```cypher
MATCH (c:Computer)-[r:MemberOf*1..]-(g:Group {name:'ALL_SERVERS@EXAMPLE.LOCAL'}) SET c.tier_1_computer = true
```

**Create a property for Tier 2 Users (group name + exclusion)**

```cypher
MATCH (u:User)-[r:MemberOf*1..]-(g:Group) WHERE g.name CONTAINS 'ALL EMPLOYEES' AND NOT u.name CONTAINS 'TEST' SET u.tier_2_user = true
```

**Create a property for Tier 2 Computers (nested group name)**

```cypher
MATCH (c:Computer)-[r:MemberOf*1..]-(g:Group) WHERE g.name STARTS WITH 'CLIENT_' SET c.tier_2_computer = true
```

**List Tier 2 access to Tier 1 Computers**

```cypher
MATCH (u)-[rel:AddMember|AdminTo|AllowedToDelegate|CanRDP|ExecuteDCOM|ForceChangePassword|GenericAll|GenericWrite|GetChangesAll|HasSession|Owns|ReadLAPSPassword|SQLAdmin|TrustedBy|WriteDACL|WriteOwner|AddAllowedToAct|AllowedToAct|MemberOf|AllExtendedRights]->(c:Computer)
WHERE u.tier_2_user = true AND c.tier_1_computer = true
RETURN u.name, TYPE(rel), c.name, labels(c)
```

**List Tier 1 Sessions on Tier 2 Computers**

```cypher
MATCH (c:Computer)-[rel:HasSession]->(u:User)
WHERE u.tier_1_user = true AND c.tier_2_computer = true
RETURN u.name, u.displayname, TYPE(rel), c.name, labels(c), c.enabled
```

---

