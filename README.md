# iftime.pl
perl utility for comparing the current or specified time with a specified interval or logical expression of intervals 

Нow it works: the utility converts an expression into a sql query, executes it through sqlite3 (in an in-memory database created on the fly) and returns the result either as an exit code, or as a number 0 or 1 

Requirements: perl, modules DBI, DBD::SQLite

Usage:
--------------------------------------------------------------------------------
usage: iftime.pl [-udprh] [-t custom_datetime] time_expression

options:

       -u      - use UTC time instead of local time
       -d      - dump SQL expressions
       -p      - print result instead returning exit code
       -r      - read time expression from file time_expression
       -n      - omits \n from printed result (if -p specified)
       -t      - override current date/time with arbitrary value
       -h      - print help message

valid elements of time/date expression:

       |       - treats as logical OR
       &       - treats as logical END
       !       - treats as logical NOT
       ()      - parentheses for logical grouping  
       {arg}   - replaces with file arg.inc searched in macro directories
       [arg]   - group of time/date conditions of same type
                 can include multiple values separated by commas  
                 as well as ranges denoted by a dashes  
                 example: [arg1-arg2,arg3]

types of time/date conditions:

       HH:MM            - time (hour and minute)
       mm.dd            - date (month and day)
       yyyy.mm.dd       - full date (year, month and day)
       yyyy.mm.dd HH:MM - full date and time
       yyyy             - date (only year)
       mmm              - date (only month, as Jun, Feb, Mar etc)
       dd               - date (only day)
       www              - date (day of week, as Sun, Mon, Tue etc,
                          and also Workdays and Weekend)

directories by default in which macro files will be searched:
~/.iftime.pl/macros:/etc/iftime.pl/macros:/var/lib/iftime.pl/macros

Examples:

iftime.pl '[weekend] | ![08:00-20:00]' && echo 'relaх time' || echo 'worktime'

iftime.pl -up -t '2022-01-01 10:00' '[09:00-12:00] & [Jan] & ![2-30] & [2022]'

--------------------------------------------------------------------------------
