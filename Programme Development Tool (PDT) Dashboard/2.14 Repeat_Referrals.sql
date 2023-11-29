SET ANSI_WARNINGS OFF
SET NOCOUNT ON

-- CREATES NEW SPELL TABLE AND BASE TABLE -------------------------------------------------------------------------------------------------

-- SELECTS ALL PEOPLE AND PATHWAYS RECORD NUMBERS AND REFRECDATES FOR v1.5 and v2.0

IF OBJECT_ID ('tempdb..#All') IS NOT NULL DROP TABLE #All

SELECT * INTO #All 

FROM (

SELECT CAST(r.[IAPT_PERSON_ID] AS VARCHAR) AS 'PseudoNumber'
		,CAST(IC_PATHWAY_ID AS VARCHAR(100)) AS 'IC_PATHWAY_ID'
		,CAST(r.[IAPT_RECORD_NUMBER] AS BIGINT) AS 'IC_RECORD_NUMBER'
		,[REFRECDATE]
		,h.[START_DATE]
		,h.[END_DATE]
		,ph.[Organisation_Code] AS 'Provider Code'
		,ch.[Organisation_Code] AS 'CCG Code' 
		,CAST([REFERRAL_ID] AS BIGINT) AS 'REFERRAL_ID'

FROM	[mesh_IAPT].[Referral_v15] r
		---------------------------------------------
		INNER JOIN [mesh_IAPT].[Person_v15] p ON r.[IAPT_RECORD_NUMBER] = p.[IAPT_RECORD_NUMBER]
		INNER JOIN [mesh_IAPT].[Header_v15] h ON p.[HEADER_ID] = h.[HEADER_ID]
		----------------------------------------------
		LEFT JOIN [Reporting].[Ref_ODS_Commissioner_Hierarchies] ch ON r.[IC_CCG] = ch.[Organisation_Code] AND ch.[Effective_To] IS NULL
		LEFT JOIN [Reporting].[Ref_ODS_Provider_Hierarchies] ph ON r.[OrgCodeProvider] = ph.[Organisation_Code] AND ph.[Effective_To] IS NULL

UNION

SELECT CAST(mpi.[pseudo_nhs_number_ncdr] AS VARCHAR) AS 'PseudoNumber'
		,CAST(PathwayID AS VARCHAR(100)) AS 'PathwayID'
		,r.[RecordNumber] AS 'RecordNumber'
		,[ReferralRequestReceivedDate]
		,l.[ReportingPeriodStartDate]
		,l.[ReportingPeriodEndDate]
		,ph.[Organisation_Code] AS 'Provider Code'
		,ch.[Organisation_Code] AS 'CCG Code' 
		,CAST([UniqueID_IDS101] AS BIGINT)

FROM	[mesh_IAPT].[IDS101referral] r
		-----------------------------------------
		INNER JOIN [mesh_IAPT].[IDS001mpi] mpi ON r.[recordnumber] = mpi.[recordnumber]
		INNER JOIN [mesh_IAPT].[IsLatest_SubmissionID] l ON r.[UniqueSubmissionID] = l.[UniqueSubmissionID] AND r.[AuditId] = l.[AuditId] AND r.[Unique_MonthID] = l.[Unique_MonthID]
		-----------------------------------------
		LEFT JOIN [Reporting].[Ref_ODS_Commissioner_Hierarchies]  ch ON r.[OrgIDComm] = ch.[Organisation_Code] AND ch.[Effective_To] IS NULL
		LEFT JOIN [Reporting].[Ref_ODS_Provider_Hierarchies] ph ON r.[OrgID_Provider] = ph.[Organisation_Code] AND ph.[Effective_To] IS NULL

WHERE IsLatest = 1 
	
) #All

-- SELECTS THE MAX RECORD NUMBER ----------------------------------------------------------------------------

IF OBJECT_ID ('tempdb..#Temp3') IS NOT NULL DROP TABLE #Temp3

SELECT IC_PATHWAY_ID,MAX(IC_RECORD_NUMBER) AS 'IC_RECORD_NUMBER'

INTO #Temp3 FROM #All

GROUP BY [IC_PATHWAY_ID]

-- ALLOCATES REFERRAL ORDER ---------------------------------------------------------------------------------

IF OBJECT_ID ('tempdb..#Spell') IS NOT NULL DROP TABLE #Spell

SELECT ROW_NUMBER() OVER(PARTITION BY r.[PseudoNumber] ORDER BY REFRECDATE DESC) AS 'ReferralOrder2'
		, r.*

INTO #Spell FROM #All r

INNER JOIN #Temp3 t on r.[IC_PATHWAY_ID] = t.[IC_PATHWAY_ID] AND r.[IC_RECORD_NUMBER] = t.[IC_RECORD_NUMBER]

-- SELECTS ALL FIELDS REQUIRED FOR SPELLS TABLE FROM v1.5 and v2.0 ------------------------------------------

IF OBJECT_ID ('tempdb..#Spell2') IS NOT NULL DROP TABLE #Spell2

SELECT * INTO #Spell2  

FROM (

SELECT s.*
		,CAST(r.[IC_USE_PATHWAY_FLAG] AS VARCHAR) AS 'IC_USE_PATHWAY_FLAG'
		,r.[AGE_AT_REF_RECEIVED_DATE]
		,CAST(r.[IC_RECOVERY_FLAG] As VARCHAR) AS 'IC_RECOVERY_FLAG'
		,CAST(r.[IC_RELIABLE_DETER_FLAG] AS VARCHAR) AS 'IC_RELIABLE_DETER_FLAG'
		,CAST(r.[IC_RELIABLE_IMPROV_FLAG] AS VARCHAR) AS 'IC_RELIABLE_IMPROV_FLAG'
		,CAST(r.[IC_NOT_CASENESS_FLAG] AS VARCHAR) AS 'IC_NOT_CASENESS_FLAG'
		,r.[ENDDATE]
		,r.[IC_ProvDiag]
		,NULL AS 'PresentingComplaintHigherCategory'
		,NULL AS 'PresentingComplaintLowerCategory'
		,r.[IC_Count_Treatment_Appointments]
		,r.[ENDCODE]
		,'v1.5' AS 'Version'

FROM #Spell s

INNER JOIN [mesh_IAPT].[Referral_v15] r on CAST(r.[IC_PATHWAY_ID] AS VARCHAR(100)) = s.[IC_PATHWAY_ID] AND [IAPT_RECORD_NUMBER] = CAST(s.[IC_RECORD_NUMBER] AS VARCHAR)

UNION

SELECT s.*
		,CAST(r.[UsePathway_Flag] AS VARCHAR) AS UsePathway_Flag
		,r.[Age_ReferralRequest_ReceivedDate]
		,CAST(r.[RECOVERY_FLAG] AS VARCHAR)
		,CAST(r.[ReliableDeterioration_Flag] AS VARCHAR)
		,CAST(r.[ReliableImprovement_Flag] AS VARCHAR)
		,CAST(r.[NotCaseness_Flag] AS VARCHAR)
		,r.[ServDischDate]
		,NULL As [IC_ProvDiag]
		,r.[PresentingComplaintHigherCategory]
		,r.[PresentingComplaintLowerCategory]
		,r.[TreatmentCareContact_Count]
		,r.[ENDCODE]
		,'v2.0' AS 'Version'

FROM #Spell s

INNER JOIN [mesh_IAPT].[IDS101referral] r on CAST([PathwayID] AS VARCHAR(100)) = s.[IC_PATHWAY_ID] AND [RecordNumber] = [IC_RECORD_NUMBER]

) #Spell2

-- SELECTS ALL 'VALID' REFERRALS (NOT LATE SUBMISSIONS) -----------------------------------------------------------------

IF OBJECT_ID ('tempdb..#ValidReferrals') IS NOT NULL DROP TABLE #ValidReferrals

SELECT DISTINCT IC_PATHWAY_ID
				,REFRECDATE

INTO #ValidReferrals FROM #All

WHERE Month(Refrecdate) = Month(START_DATE) AND Year(Refrecdate) = Year(START_DATE) 

-- CREATE BASE TABLE FOR QUERY ------------------------------------------------------------------------------------------

IF OBJECT_ID ('tempdb..#RepeatReferrals') IS NOT NULL DROP TABLE #RepeatReferrals

SELECT DISTINCT a.PseudoNumber
,'No Match' AS 'LatestProvider'
,'No Match' AS 'PreviousProvider'
,'No Match' AS 'LatestCCG'
,'No Match' AS 'PreviousCCG'
,a.[REFRECDATE] AS 'LatestReferral'
,b.[REFRECDATE] AS 'PreviousReferral'
,a.[IC_USE_PATHWAY_FLAG] AS 'LatestFlag'
,b.[IC_USE_PATHWAY_FLAG] AS 'PreviousFlag'
,a.[AGE_AT_REF_RECEIVED_DATE] AS 'LatestAge'
,b.[AGE_AT_REF_RECEIVED_DATE] AS 'PreviousAge'
,b.[IC_RECOVERY_FLAG] AS 'PreviousRecovery'
,b.[IC_RELIABLE_DETER_FLAG] AS 'PreviousDeterioration'
,b.[IC_RELIABLE_IMPROV_FLAG] AS 'PreviousImprovement'
,b.[IC_NOT_CASENESS_FLAG] AS 'PreviousNotCaseness'
,DATEDIFF(Day,b.[ENDDATE],a.[REFRECDATE]) AS 'Time between referrals'
,CASE WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] LIKE 'F32%' OR a.[IC_ProvDiag] LIKE 'F33%' THEN 'F32 or F33 - Depression'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] = 'F400' THEN 'F400 - Agoraphobia'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] = 'F401' THEN 'F401 - Social Phobias'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] = 'F402' THEN 'F402 care- Specific Phobias'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] = 'F410' THEN 'F410 - Panic Disorder'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] = 'F411' THEN 'F411 - Generalised Anxiety'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] = 'F412' THEN 'F412 - Mixed Anxiety'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] LIKE 'F42%' THEN 'F42 - Obsessive Compulsive'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] = 'F431' THEN 'F431 - Post-traumatic Stress'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] = 'F452' THEN 'F452 - Hypochondrial disorder'
		WHEN a.[Version] = 'v1.5' AND LEFT(a.[IC_ProvDiag],3) between 'F40' and 'F43' and a.[IC_ProvDiag] not in ('F400','F401','F402','F410','F411','F412','F431', 'F452') and a.[IC_ProvDiag] not like 'F42%' THEN 'Other F40 to 43 - Other Anxiety'
		WHEN a.[Version] = 'v1.5' AND a.[IC_ProvDiag] not in ('F400','F401','F402','F410','F411','F412','F431', 'F452') and a.[IC_ProvDiag] not like 'F42%' AND LEFT(a.[IC_ProvDiag],3) not between 'F40' and 'F43' THEN 'With no code/Other F/Other Recorded'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Depression' THEN 'F32 or F33 - Depression'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Unspecified' THEN 'Unspecified'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Other recorded problems' THEN 'Other recorded problems'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Other Mental Health problems' THEN 'Other Mental Health problems'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Invalid Data supplied' THEN 'Invalid Data supplied'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = '83482000 Body Dysmorphic Disorder' THEN '83482000 Body Dysmorphic Disorder'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'F400 - Agoraphobia' THEN 'F400 - Agoraphobia'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'F401 - Social phobias' THEN 'F401 - Social Phobias'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'F402 - Specific (isolated) phobias' THEN 'F402 care- Specific Phobias'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'F410 - Panic disorder [episodic paroxysmal anxiety' THEN 'F410 - Panic Disorder'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'F411 - Generalised Anxiety Disorder' THEN 'F411 - Generalised Anxiety'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'F412 - Mixed anxiety and depressive disorder' THEN 'F412 - Mixed Anxiety'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'F42 - Obsessive-compulsive disorder' THEN 'F42 - Obsessive Compulsive'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'F431 - Post-traumatic stress disorder' THEN 'F431 - Post-traumatic Stress'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'F452 Hypochondriacal Disorders' THEN 'F452 - Hypochondrial disorder'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] = 'Other F40-F43 code' THEN 'Other F40 to 43 - Other Anxiety'
		WHEN a.[Version] = 'v2.0' AND a.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND a.[PresentingComplaintLowerCategory] IS NULL THEN 'No Code'
		ELSE 'Other' END AS 'LatestDiagnosis'
		,CASE WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] LIKE 'F32%' OR b.[IC_ProvDiag] LIKE 'F33%' THEN 'F32 or F33 - Depression'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] = 'F400' THEN 'F400 - Agoraphobia'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] = 'F401' THEN 'F401 - Social Phobias'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] = 'F402' THEN 'F402 care- Specific Phobias'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] = 'F410' THEN 'F410 - Panic Disorder'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] = 'F411' THEN 'F411 - Generalised Anxiety'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] = 'F412' THEN 'F412 - Mixed Anxiety'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] LIKE 'F42%' THEN 'F42 - Obsessive Compulsive'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] = 'F431' THEN 'F431 - Post-traumatic Stress'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] = 'F452' THEN 'F452 - Hypochondrial disorder'
		WHEN b.[Version] = 'v1.5' AND LEFT(b.[IC_ProvDiag],3) between 'F40' and 'F43' and b.[IC_ProvDiag] not in ('F400','F401','F402','F410','F411','F412','F431', 'F452') and b.[IC_ProvDiag] not like 'F42%' THEN 'Other F40 to 43 - Other Anxiety'
		WHEN b.[Version] = 'v1.5' AND b.[IC_ProvDiag] not in ('F400','F401','F402','F410','F411','F412','F431', 'F452') and b.[IC_ProvDiag] not like 'F42%' AND LEFT(b.[IC_ProvDiag],3) not between 'F40' and 'F43' THEN 'With no code/Other F/Other Recorded'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Depression' THEN 'F32 or F33 - Depression'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Unspecified' THEN 'Unspecified'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Other recorded problems' THEN 'Other recorded problems'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Other Mental Health problems' THEN 'Other Mental Health problems'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Invalid Data supplied' THEN 'Invalid Data supplied'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = '83482000 Body Dysmorphic Disorder' THEN '83482000 Body Dysmorphic Disorder'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'F400 - Agoraphobia' THEN 'F400 - Agoraphobia'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'F401 - Social phobias' THEN 'F401 - Social Phobias'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'F402 - Specific (isolated) phobias' THEN 'F402 care- Specific Phobias'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'F410 - Panic disorder [episodic paroxysmal anxiety' THEN 'F410 - Panic Disorder'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'F411 - Generalised Anxiety Disorder' THEN 'F411 - Generalised Anxiety'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'F412 - Mixed anxiety and depressive disorder' THEN 'F412 - Mixed Anxiety'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'F42 - Obsessive-compulsive disorder' THEN 'F42 - Obsessive Compulsive'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'F431 - Post-traumatic stress disorder' THEN 'F431 - Post-traumatic Stress'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'F452 Hypochondriacal Disorders' THEN 'F452 - Hypochondrial disorder'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] = 'Other F40-F43 code' THEN 'Other F40 to 43 - Other Anxiety'
		WHEN b.[Version] = 'v2.0' AND b.[PresentingComplaintHigherCategory] = 'Anxiety and stress related disorders (Total)' AND b.[PresentingComplaintLowerCategory] IS NULL THEN 'No Code' 
		ELSE 'Other' END AS 'PreviousDiagnosis'
		,b.[IC_Count_Treatment_Appointments] AS 'PreviousCountAppointments'
		,b.[ENDDATE] AS 'PreviousEndDate'
		,CASE WHEN b.[ENDCODE] = '10' THEN 'Ended Not Suitable'
				WHEN b.[ENDCODE] = '11' THEN 'Ended Signposted'
				WHEN b.[ENDCODE] = '12' THEN 'Ended Mutual Agreement'
				WHEN b.[ENDCODE] = '13' THEN 'Ended Referred Elsewhere'
				WHEN b.[ENDCODE] = '14' THEN 'Ended Declined'
				WHEN b.[ENDCODE] = '15' THEN 'Ended Deceased Assessed Only'
				WHEN b.[ENDCODE] = '97' THEN 'Ended Unknown Assessed Only'
				WHEN b.[ENDCODE] = '40' THEN 'Ended Stepped Up'
				WHEN b.[ENDCODE] = '41' THEN 'Ended Stepped Down'
				WHEN b.[ENDCODE] = '42' THEN 'Ended Completed'
				WHEN b.[ENDCODE] = '43' THEN 'Ended Dropped Out'
				WHEN b.[ENDCODE] = '44' THEN 'Ended Referred Non IAPT'
				WHEN b.[ENDCODE] = '45' THEN 'Ended Deceased Treated'
				WHEN b.[ENDCODE] = '98' THEN 'Ended Unknown Treated'
				when b.[ENDCODE] = '50' then 'Ended Not Assessed'
				when b.[ENDCODE] = '16' then 'Ended Incomplete Assessment'
				when b.[ENDCODE] = '17' then 'Ended Deceased (Seen but not taken on for a course of treatment)'
				when b.[ENDCODE] = '95' then 'Ended Not Known (Seen but not taken on for a course of treatment)'
				when b.[ENDCODE] = '46' then 'Ended Mutually agreed completion of treatment'
				when b.[ENDCODE] = '47' then 'Ended Termination of treatment earlier than Care Professional planned'
				when b.[ENDCODE] = '48' then 'Ended Termination of treatment earlier than patient requested'
				when b.[ENDCODE] = '49' then 'Ended Deceased (Seen and taken on for a course of treatment)'
				when b.[ENDCODE] = '96' then 'Ended Not Known (Seen and taken on for a course of treatment)'
		 END AS 'EndCode'
		,a.[IC_PATHWAY_ID] AS 'LatestID'
		,b.[IC_PATHWAY_ID] AS 'PreviousID'
		,a.[ReferralOrder2] AS 'LatestRowID'
		,b.[ReferralOrder2] AS 'PreviousRowID'

INTO #RepeatReferrals

FROM #Spell2 a
	INNER JOIN #Spell2 b ON a.[PseudoNumber] = b.[PseudoNumber] AND a.[ReferralOrder2] = (b.[ReferralOrder2] -1)
	INNER JOIN #ValidReferrals v ON a.[IC_PATHWAY_ID] = v.[IC_PATHWAY_ID] AND a.[REFRECDATE] = v.[REFRECDATE]

WHERE b.[ENDDATE] IS NOT NULL AND a.[PseudoNumber] <> '0' AND a.[PseudoNumber] IS NOT NULL AND b.[PseudoNumber] <> '0' AND b.[PseudoNumber] IS NOT NULL

-- SELECTS THE FIRST [Provider Code] LISTED (MATCHES REFERRAL COUNT ORG) -- For v2.0 the REFERRAL_ID field contains UniqueID_IDS101

IF OBJECT_ID ('tempdb..#Record2') IS NOT NULL DROP TABLE #Record2

SELECT	[IC_PATHWAY_ID]
		,MAX([REFERRAL_ID]) AS 'REFERRAL_ID'

INTO #Record2 FROM #All

WHERE Month(Refrecdate) = Month(START_DATE) AND Year(Refrecdate) = Year(START_DATE) 

GROUP BY [IC_PATHWAY_ID]

---------------------------------------------------------------------------------------------------

UPDATE #RepeatReferrals
SET LatestCCG =  CASE WHEN [CCG Code] IS NULL THEN 'Other' ELSE a.[CCG Code] END
FROM #RepeatReferrals r
INNER JOIN #All a ON [LatestID] = a.[IC_Pathway_ID]
INNER JOIN #Record2 m ON m.[IC_PATHWAY_ID] = [LatestID] AND m.[REFERRAL_ID] = a.[REFERRAL_ID]

UPDATE #RepeatReferrals
SET PreviousCCG =  CASE WHEN [CCG Code] IS NULL THEN 'Other' ELSE a.[CCG Code] END
FROM #RepeatReferrals r
INNER JOIN #All a ON PreviousID = a.IC_Pathway_ID
INNER JOIN #Record2 m ON m.[IC_PATHWAY_ID] = [PreviousID] AND m.[REFERRAL_ID] = a.[REFERRAL_ID]

UPDATE #RepeatReferrals
SET LatestProvider =  CASE WHEN [Provider Code] IS NULL THEN 'Other' ELSE a.[Provider Code] END
FROM #RepeatReferrals r
INNER JOIN #All a ON [LatestID] = a.[IC_Pathway_ID]
INNER JOIN #Record2 m ON m.[IC_PATHWAY_ID] = [LatestID] AND m.[REFERRAL_ID] = a.[REFERRAL_ID]

UPDATE #RepeatReferrals
SET PreviousProvider =  CASE WHEN [Provider Code] IS NULL THEN 'Other' ELSE a.[Provider Code] END
FROM #RepeatReferrals r
INNER JOIN #All a ON [PreviousID] = a.[IC_Pathway_ID]
INNER JOIN #Record2 m ON m.[IC_PATHWAY_ID] = [PreviousID] AND m.[REFERRAL_ID] = a.[REFERRAL_ID]

-- Repeat Referrals Table ----------------------------------------------------------------------------------------------------

-- The full table has to be re-run each month ---------------------

DELETE FROM [MHDInternal].[DASHBOARD_TTAD_PDT_RepeatReferrals]

DECLARE @Offset INT = -1

WHILE @Offset > -33

BEGIN 

DECLARE @Period_Start AS DATE = (SELECT DATEADD(MONTH,@Offset,MAX([ReportingPeriodStartDate])) FROM [mesh_IAPT].[IsLatest_SubmissionID])
DECLARE @Period_end AS DATE = (SELECT DATEADD(MONTH,@Offset,MAX([ReportingPeriodEndDate])) FROM [mesh_IAPT].[IsLatest_SubmissionID])

INSERT INTO [MHDInternal].[DASHBOARD_TTAD_PDT_RepeatReferrals]

SELECT * FROM (

SELECT DATENAME(m, @Period_Start) + ' ' + CAST(DATEPART(yyyy, @Period_Start) AS VARCHAR) AS 'Month'
		,CASE WHEN ch.[Region_Code]  IS NOT NULL THEN ch.[Region_Code] ELSE 'Other' END AS 'Region Code'
		,CASE WHEN ch.[Region_Name] IS NOT NULL THEN ch.[Region_Name] ELSE 'Other' END AS 'Region Name'
		,CASE WHEN ch.[Organisation_Code] IS NOT NULL THEN ch.[Organisation_Code] ELSE 'Other' END AS 'CCG Code'
		,CASE WHEN ch.[Organisation_Name] IS NOT NULL THEN ch.Organisation_Name ELSE 'Other' END AS 'CCG Name' 
		,CASE WHEN ph.[Organisation_Code] IS NOT NULL THEN ph.[Organisation_Code] ELSE 'Other' END AS 'Provider Code'
		,CASE WHEN ph.[Organisation_Name] IS NOT NULL THEN ph.[Organisation_Name] ELSE 'Other' END AS 'Provider Name'
		,CASE WHEN ch.[STP_Code] IS NOT NULL THEN ch.[STP_Code] ELSE 'Other' END AS 'STP Code'
		,CASE WHEN ch.[STP_Name] IS NOT NULL THEN ch.[STP_Name] ELSE 'Other' END AS 'STP Name'
		,'Problem Descriptor' AS 'Category'
		,[LatestDiagnosis] AS 'LatestDiagnosis'
		,[PreviousDiagnosis] AS 'PreviousDiagnosis'
		,COUNT(DISTINCT CASE WHEN [Time between referrals] < 92 THEN LatestID END) AS '91 days or fewer'
		,COUNT(DISTINCT CASE WHEN [Time between referrals] BETWEEN 92 AND 182 THEN LatestID END) AS '92-182 days'
		,COUNT(DISTINCT CASE WHEN [Time between referrals] BETWEEN 183 AND 273 THEN LatestID END) AS '183-273 days'
		,COUNT(DISTINCT CASE WHEN [Time between referrals] > 273 THEN LatestID END) AS 'More than 273 days'

FROM	#RepeatReferrals rr
		------------------
		LEFT JOIN [Reporting_UKHD_ODS].[Commissioner_Hierarchies] ch ON rr.[LatestCCG] = ch.[Organisation_Code] AND ch.[Effective_To] IS NULL
		LEFT JOIN [Reporting_UKHD_ODS].[Provider_Hierarchies] ph ON rr.[LatestProvider] = ph.[Organisation_Code] AND ph.[Effective_To] IS NULL

WHERE LatestReferral BETWEEN @Period_Start AND @Period_end 
		AND [Time between referrals] BETWEEN 0 AND 365  
		AND [PreviousCountAppointments] >= 2 
		AND [LatestID] <> [PreviousID] 
		AND [PseudoNumber] IS NOT NULL 
		AND [LatestReferral] <> [PreviousReferral] 
		AND [PseudoNumber] <> '0'

GROUP BY CASE WHEN ch.[Region_Code]  IS NOT NULL THEN ch.[Region_Code] ELSE 'Other' END 
		,CASE WHEN ch.[Region_Name] IS NOT NULL THEN ch.[Region_Name] ELSE 'Other' END 
		,CASE WHEN ch.[Organisation_Code] IS NOT NULL THEN ch.[Organisation_Code] ELSE 'Other' END 
		,CASE WHEN ch.[Organisation_Name] IS NOT NULL THEN ch.[Organisation_Name] ELSE 'Other' END 
		,CASE WHEN ph.[Organisation_Code] IS NOT NULL THEN ph.[Organisation_Code] ELSE 'Other' END
		,CASE WHEN ph.[Organisation_Name] IS NOT NULL THEN ph.[Organisation_Name] ELSE 'Other' END
		,CASE WHEN ch.[STP_Code] IS NOT NULL THEN ch.[STP_Code] ELSE 'Other' END 
		,CASE WHEN ch.[STP_Name] IS NOT NULL THEN ch.[STP_Name] ELSE 'Other' END 
		,[LatestDiagnosis]
		,[PreviousDiagnosis]
			
)_

SET @Offset = @Offset - 1
END
GO

---- Repeat referrals Insert table -------------------------------------------------------------------------

DELETE FROM [MHDInternal].[DASHBOARD_TTAD_PDT_RepeatReferrals_Insert]

DECLARE @Offset INT = -1

WHILE @Offset > -36

BEGIN 

DECLARE @Period_Start AS DATE = (SELECT DATEADD(MONTH,@Offset,MAX([ReportingPeriodStartDate])) FROM [mesh_IAPT].[IsLatest_SubmissionID])
DECLARE @Period_end AS DATE = (SELECT DATEADD(MONTH,@Offset,MAX([ReportingPeriodEndDate])) FROM [mesh_IAPT].[IsLatest_SubmissionID])

PRINT @Period_Start
PRINT @Period_End

INSERT INTO [MHDInternal].[DASHBOARD_TTAD_PDT_RepeatReferrals_Insert]

SELECT DATENAME(m, @Period_Start) + ' ' + CAST(DATEPART(yyyy, @Period_Start) AS VARCHAR) AS 'Month'
		,CASE WHEN ch.[Region_Code] IS NOT NULL THEN ch.[Region_Code] ELSE 'Other' END AS 'Region Code'
		,CASE WHEN ch.[Region_Name] IS NOT NULL THEN ch.[Region_Name] ELSE 'Other' END AS 'Region Name'
		,CASE WHEN ch.[Organisation_Code] IS NOT NULL THEN ch.[Organisation_Code] ELSE 'Other' END AS 'CCG Code'
		,CASE WHEN ch.[Organisation_Name] IS NOT NULL THEN ch.Organisation_Name ELSE 'Other' END AS 'CCG Name' 
		,CASE WHEN ph.[Organisation_Code] IS NOT NULL THEN ph.[Organisation_Code] ELSE 'Other' END AS 'Provider Code'
		,CASE WHEN ph.[Organisation_Name] IS NOT NULL THEN ph.[Organisation_Name] ELSE 'Other' END AS 'Provider Name'
		,CASE WHEN ch.[STP_Code] IS NOT NULL THEN ch.[STP_Code] ELSE 'Other' END AS 'STP Code'
		,CASE WHEN ch.[STP_Name] IS NOT NULL THEN ch.[STP_Name] ELSE 'Other' END AS 'STP Name'
	,'Total' AS Category
	,'Total' AS Variable
	,COUNT (DISTINCT LatestID) AS 'Repeat Referrals'

FROM	#RepeatReferrals rr
		------------------
		LEFT JOIN [Reporting_UKHD_ODS].[Commissioner_Hierarchies] ch ON rr.[LatestCCG] = ch.[Organisation_Code] AND ch.[Effective_To] IS NULL
		LEFT JOIN [Reporting_UKHD_ODS].[Provider_Hierarchies] ph ON rr.[LatestProvider] = ph.[Organisation_Code] AND ph.[Effective_To] IS NULL

WHERE LatestReferral BETWEEN @Period_Start AND @Period_end AND [Time between referrals] BETWEEN 0 AND 365  AND [PreviousCountAppointments] >= 2 
AND [LatestID] <> [PreviousID] AND [PseudoNumber] IS NOT NULL AND [LatestReferral] <> [PreviousReferral] AND [PseudoNumber] <> '0'

GROUP BY CASE WHEN ch.[Region_Code] IS NOT NULL THEN ch.[Region_Code] ELSE 'Other' END
		,CASE WHEN ch.[Region_Name] IS NOT NULL THEN ch.[Region_Name] ELSE 'Other' END
		,CASE WHEN ch.[Organisation_Code] IS NOT NULL THEN ch.[Organisation_Code] ELSE 'Other' END
		,CASE WHEN ch.[Organisation_Name] IS NOT NULL THEN ch.[Organisation_Name] ELSE 'Other' END
		,CASE WHEN ph.[Organisation_Code] IS NOT NULL THEN ph.[Organisation_Code] ELSE 'Other' END
		,CASE WHEN ph.[Organisation_Name] IS NOT NULL THEN ph.[Organisation_Name] ELSE 'Other' END
		,CASE WHEN ch.[STP_Code] IS NOT NULL THEN ch.[STP_Code] ELSE 'Other' END
		,CASE WHEN ch.[STP_Name] IS NOT NULL THEN ch.[STP_Name] ELSE 'Other' END

SET @Offset = @Offset - 1
END

-- Update [RepeatReferrals2] in [DASHBOARD_TTAD_PDT_Inequalities] from [DASHBOARD_TTAD_PDT_RepeatReferrals_Insert]-------------------

UPDATE [MHDInternal].[DASHBOARD_TTAD_PDT_Inequalities] SET [RepeatReferrals2] = NULL
UPDATE [MHDInternal].[DASHBOARD_TTAD_PDT_Inequalities] SET [RepeatReferrals2] = b.[Repeat Referrals]

FROM [MHDInternal].[DASHBOARD_TTAD_PDT_RepeatReferrals_Insert] b

INNER JOIN [MHDInternal].[DASHBOARD_TTAD_PDT_Inequalities] a ON a.[Month] = b.[Month] 
			AND a.[Region Code] = b.[Region Code] 
			AND a.[CCG Code] = b.[CCG Code] AND a.[Provider Code] = b.[Provider Code]
			AND a.[STP Code] = b.[STP Code] AND a.[Category] = b.[Category] 
			AND (a.[Variable] = b.[Variable] OR a.[Variable] IS NULL AND b.[Variable] IS NULL)

------------------------------------------------------------------------------------------------------------------------------------

PRINT CHAR(10)
PRINT 'Updated - [MHDInternal].[DASHBOARD_TTAD_PDT_RepeatReferrals]'
PRINT 'Updated - [MHDInternal].[DASHBOARD_TTAD_PDT_RepeatReferrals_Insert]'
