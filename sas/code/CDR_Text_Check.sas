/*******************************************
 * $ID:$lwright
 * 
 * Copyright(c) 2025 SAS Institute Inc., Cary, NC, USA. All Rights Reserved.
 *
 * Name: CDR_Text_Check.sas
 *
 * Purpose: search custom concepts for text string and return the concepts containing the text
 *
 * Author(s): Lois Wright (lois.wright@sas.com)
 *
 * Support: SAS(r) US Professional Services
 *
 * Input: text files in local git repository of custom concepts for a model
 *
 * Output: SAS data set listing all custom concepts containing the text that was searched for
 *			if no concept contains the text then 'no concept contains the text' is displayed
 *
 * Parameters: user id, git directory, model name, path to directory containing text files (one for each custom concept)
 *
 * Dependencies/Assumptions: Each custom concept in the model of interest has been exported to the git repository
 *
 * Usage: check for text string in model concepts
 *
 *******************************************/
/* ASSUMPTION: the program to export all custom concepts to the git repo for model of interest has been executed */
/* specify user id */
%let user_id=lwright;
/* specify name of git repository directory */
%let git_dir=vta_version_control;
/* specify project name */
%let projname = %str(Color_Project);

/* path to concepts folder */
%let cncpt_folder = /shared/workspace/&user_id./&git_dir./&projname./_concept_definition_rules/Pipeline 1/Concepts/;

/* use macro variable below to find any concept containing this text */
%let text_var=%nrstr(REMOVE_ITEM:);

/* use macro variable below to find any instances with incorrect order of elements */
*%let text_var=%nrstr(REMOVE_ITEM:%(ALIGNED,%"D);

/* use macro variable below to confirm all instances have correct order of elements */
*%let text_var=%nrstr(REMOVE_ITEM:%(ALIGNED,%"_c);

%macro findtext(model_name=);
	
    /* get list of filenames from the cncpt_folder recursively */
    /* ------------------------------------------------------------------------------------ */
    /* from paper, https://www.lexjansen.com/wuss/2012/55.pdf by Jack Hamilton */
    data dirs_found (compress=no);
        length Root $170.;
        root = "&cncpt_folder.";
        output;
    run;
    data
    dirs_found /* Updated list of directories searched */
    files_found (compress=no); /* Names of files found. */
    keep Path FileName FileType;
    length fref $8 Filename $170 FileType $170;
    /* Read the name of a directory to search. */
    modify dirs_found;
    /* Make a copy of the name, because we might reset root. */
    *Path = tranwrd(root,'\','/');
    Path = root;
    /* For the use and meaning of the FILENAME, DOPEN, DREAD, MOPEN, and */
    /* DCLOSE functions, see the SAS OnlineDocs. */
    rc = filename(fref, path);
    if rc = 0 then
        do;
            did = dopen(fref);
            rc = filename(fref);
        end;
    else
        do;
            length msg $200.;
            msg = sysmsg();
            putlog msg=;
            did = .;
        end;
    if did <= 0
        then
        do;
            putlog 'ERR' 'OR: Unable to open ' Path=;
            return;
    end;
    dnum = dnum(did);
    do i = 1 to dnum;
        filename = dread(did, i);
        fid = mopen(did, filename);
        /* It's not explicitly documented, but the SAS online */
        /* examples show that a return value of 0 from mopen */
        /* means a directory name, and anything else means */
        /* a file name. */
        if fid > 0
        then
        do;
        /* FileType is everything after the last dot. If */
            /* no dot, then no extension. */
            FileType = prxchange('s/.*\.{1,1}(.*)/$1/', 1, filename);
            if filename = filetype then filetype = ' ';
            output files_found;
        end;
        else
        do;
            /* A directory name was found; calculate the complete */
            /* path, and add it to the dirs_found data set, */
            /* where it will be read in the next iteration of this */
            /* data step. */
            root = catt(path, "/", filename);
            output dirs_found;
        end;
    end;
    rc = dclose(did);
    run;
    /* proc print data=dirs_found; */
    /* run; */
    /* proc print data=files_found; */
    /* run; */
    /* ------------------------------------------------------------------------------------ */
    proc sort data=files_found;
    by filename;
    run;
    /* filter to text files */
    data cpt_fns;
        set files_found;
        if filetype = 'txt' then output;
    run;
    /* truncate filename to create source concept name, create macvars */
    data cpts_src;
        set cpt_fns end=end;
        src_cpt = substr(filename,1,length(filename)-4);
        count+1;
        call symputx('read'||put(count,4.-l),cats(path,"/",filename));
        call symputx('dset'||put(count,4.-l),scan(filename,1,'.'));
        if end then call symputx('max',count);
    run;
    %put _user_;
	/* import each custom text file for the model of interest to search each line for a text string */
	/* options nomprint nosymbolgen; */
	%macro readin;
	   %do i=1 %to &max;
	
	      data &&dset&i;
	        infile "&&read&i" length=len;
			input line $varying32767. len;
			if missing(line) then delete; /* remove empty lines */
			*if find(line,"#") = 1 then output; /* keep only comments for this exercise */
			if find(line,"#") = 1 then delete; /* remove comments for this exercise */
	       run;
	
	   %end;
	%mend readin;
	
	%readin;
	
	options nonotes; /* max log easily reached so suppress notes */
	/* options notes; */
	/* options mprint symbolgen; */
	/* options nomprint nosymbolgen; */
	/* find whether each header contains appropriate information */
	/* required info 1) concept name 2) document type 3) purpose 4) created 5) copyright 6) all rights reserved */
	/* optional info 1) supports */
	%macro hdr_info_exists;
		proc sql;
			create table cncpts_hdr_info /* create empty table to append to */
			(
				concept_name varchar length=40 format=$40. label="concept_name",
				Proj_name varchar length=38 format=$38. label="Proj_name"
			);
		quit;
	
			%do j=1 %to &max.; /* for each custom custom concept */
	
				data out_&j. (drop=line);
					set &&dset&j;
					concept_name = "&&dset&j";
					if find(line,"&text_var","i") > 0 then output;
				run;
	
				data _NULL_; /* create macvar of obs in previous data set */
				    IF 0 THEN SET out_&j. NOBS=N;
					CALL SYMPUTX('NOBS', N);
					STOP;
				run;
	
				%if &NOBS. ge 1 %then %do; /* create list that passed criteria */
					PROC SQL;
						create table cncpt as
						select distinct 
							concept_name length=40 format=$40.
							,"&model_name." as Proj_name length=38 format=$38.
						from out_&j.;
					QUIT;
					proc append base=cncpts_hdr_info data=cncpt;
					run;
					proc sql;
						drop table cncpt;
					quit;
				%end;
	
				proc sql;
					drop table out_&j.; /* delete out data set */
				quit;
	
			%end; /* repeat for each custom concept */
	
			data _NULL_; /* create macvar of obs in concept data set */
			    IF 0 THEN SET cncpts_hdr_info NOBS=N;
				CALL SYMPUTX('NOBS', N);
				STOP;
			run;
	
			%if &NOBS. < 1 %then %do; /* populate with message if empty */			
				data cncpt;
					format concept_name $40. Proj_name $38.;
					concept_name='no concept contains the text';
					Proj_name = "&model_name.";
				run;
				proc append base=cncpts_hdr_info data=cncpt;
				run;
				proc sql;
					drop table cncpt;
				quit;
			%end;
	%mend hdr_info_exists;
	%hdr_info_exists;
	/* list of distinct concepts with text_var present */
	proc sql;
		create table cncpts_verify as
		select distinct 
			concept_name
			,Proj_name
		from cncpts_hdr_info
	;
	quit;
%mend;

%findtext(model_name=&projname);

proc print data=cncpts_verify (keep=concept_name) noobs;
title;
title "Concepts in &projname containing the text --> &text_var";
run;

/* end of code */
