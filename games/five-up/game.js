/* Five Up: guess the five-letter word in six tries, three minutes on the clock. */
(function () {
  'use strict';
  var D = window.Dailies;

  var ANSWERS = 'about above actor adapt admit adopt adult after again agent agree ahead alarm album alert alike alive allow alone along alter among angel angle ankle apple apply apron arena argue arise armor aroma arrow aside asset attic audio avoid awake award aware bacon badge bagel baker basic basil basin batch beach beard beast began begin being bench berry birth black blade blame blank blast blaze blend bless blink bliss block bloom blown board boast boost booth bound brain brake brand brave bread break brick bride brief bring brisk broad broke brook broom brown brush buddy build built bunch burst buyer cabin cable camel candy canoe cargo carry carve catch cause cedar chain chair chalk champ chant charm chart chase cheap check cheek cheer chess chest chief child chili chill chirp choir chord chose chunk cider civic claim clamp clash class clean clear clerk click cliff climb cloak clock close cloth cloud clown coach coast cocoa color comet comic coral couch could count court cover crack craft crane crash crate crawl crazy cream creek crest crisp cross crowd crown crumb crush crust curve cycle daily dairy daisy dance dealt decal decor delay dense depth diary diner dizzy dodge doing donut doubt dough dozen draft drain drama drank drape drawn dream dress dried drift drill drink drive drove dusty dwell eager eagle early earth easel eight elbow elder elect elite empty enjoy enter entry equal error essay event every exact exist extra fable faint fairy faith false fancy favor feast fence ferry fetch fever fiber field fifth fifty final first flake flame flash fleet float flock flood floor flour flown fluff fluid flute focus force forge forth forty found frame fresh fried front frost fruit fudge fully funny fuzzy giant given glade glass glaze gleam glide globe glory glove going grace grade grain grand grant grape graph grasp grass great green greet grill grind groom group grove grown guard guess guest guide habit handy happy harsh haste hasty hatch heard heart heavy hedge hello hobby honey honor horse hotel hound house hover human humor hurry ideal image index inner input irony issue ivory jelly jewel joint jolly judge juice juicy jumbo jumpy kayak kiosk knack kneel knelt knock known koala label labor ladle lance large laser latch later laugh layer learn lease least leave ledge legal lemon level lever light lilac limit linen llama local lodge logic loose lower loyal lunar lunch magic major maker mango maple march marry marsh match maybe mayor meant medal media melon mercy merge merit merry metal meter might minor minus mixed model moist money month moose moral motor mount mouse mouth movie muddy music nacho naval nerve never newly night ninth noble noise north notch novel nurse nylon oasis occur ocean offer often olive onion opera orbit order organ other otter ought ounce outer owner paint panda panel paper party pasta paste patch pause peace peach pearl pedal penny perch petal phone photo piano piece pilot pinch pitch pixel pizza place plaid plain plane plant plate plaza pluck plumb plume plush point polar porch pouch pound power press price pride prime print probe proof proud prove prune pulse punch pupil puppy purse quack quail queen query quest quick quiet quilt quirk quite quote radar radio rainy raise rally ranch range rapid ratio reach react ready realm rebel refer reign relax relay renew reply rhyme rider ridge right rinse ripen risen river roast robin robot rocky rough round route royal rugby ruler rumor rural rusty salad sandy sauce scale scarf scene scent scoop scope score scout scrap scrub seven shade shady shake shall shape share shark sharp shawl sheep sheet shelf shell shift shine shiny shirt shock shone shook shore short shout shown shrub sight silky silly since sixth sixty skate skill skirt slate sleep slice slide slope small smart smell smile smoke snack snail sneak snowy solar solid solve sorry sound south space spare spark speak speed spell spend spent spice spicy spill spine spoke spoon sport spray squad stack staff stage stain stair stake stale stall stamp stand stare start state steam steel steep steer stern stick still sting stock stone stood stool store storm story stout stove straw stray strip stuck study stuff style sugar suite sunny super surge swamp swarm sweep sweet swept swift swing swirl sword syrup table taken tango taste tasty teach teeth tempo tenth thank theme there thick thing think third thorn those three threw throw thumb tidal tiger tight timer tired title toast today token tooth topic torch total touch tough towel tower trace track trade trail train trait treat trend trial tribe trick tried troop trout truck truly trunk trust truth tulip tutor twice twine twirl twist ultra uncle under union unite unity until upper upset urban usage usual utter valid value valve vapor vault verse video vigor vinyl viola visit vital vivid vocal voice voter wafer wagon waist watch water weary weave wedge weigh whale wheat wheel where which while whirl white whole whose wider windy witty woman world worry worth would woven wrist write wrote yacht yearn yeast yield young youth zebra zesty'.toUpperCase().split(' ');
  var EXTRA = 'abaciabackabaftabaseabashabateabbeyabbotabeamabetsabhorabideablerabodeabortabutsabuzzabyssachedachesachooacidsacingacmesacornacresacridactedacuteadageaddedadderaddleadeptadieuadmanadmenadminadobeadoreadornadzesaegisaeonsaerieaffixafireafootafoulagapeagateagaveagileagingagismaglowagonyaidedaidesailedaimedairedaislealderalgaealiasalibialienalignalineallayalleyallotalloyaloesaloftalohaaloofaloudalphaaltaralthoaltosalumsamassamazeamberambleamebaameeramendamigoaminoamirsamissamityamourampleamplyampulamuckamuseangerangryangstanimeanionaniseankhsannexannoyannulanodeanonsantedantesanticantisanvilaortaapaceapartaphidapingappalapsesapteraptlyaquaeaquasarborarcedardorareasargonargotariasarmedarosearrayarsonartsyascotashedashenashesaskedaskewaspenaspicassayassesasterastiratlasatollatomsatoneatriaattarauditaugeraughtaugurauntsauraeauralaurasautosavailavastaversavertavianavowsawaitawashawfulawingawokeaxialaxingaxiomaxlesaxonsazurebaaedbabelbabesbacksbadlybaggybailsbaitsbaizebakedbakesbaldsbaledbalesbalksbalkyballsbalmsbalmybalsabanalbandsbandybanesbangsbanjobanksbannsbarbsbardsbaredbarerbaresbarfsbargebarksbarnsbaronbasalbasedbaserbasesbasisbasksbassibassobastebatedbatesbathebathsbatikbatonbattybaudsbawdybawlsbayedbayoubeadsbeadybeaksbeamsbeansbearsbeatsbeausbeauxbebopbecksbeechbeefsbeefybeepsbeersbeetsbefitbefogbegatbegetbegotbegunbeigebelaybelchbeliebellebellsbellybelowbeltsbendsbentsberetbergsbermsberthberylbesetbesombesotbestsbetasbevelbiblebicepbiddybidedbidesbidetbiersbiffsbightbigotbikedbikerbikesbilgebilksbillsbillybindsbingebingobipedbirchbirdsbisonbitesblabsblandblareblatsbleakbleatbleedbleepblentblestblimpblindblingblipsblitzbloatblobsblocsblogsblondbloodblotsblowsbluedbluerbluesbluffbluntblurbblursblurtblushboarsboatsbobbybodedbodesbogeyboggybogiebogusboilsbolasbolesbollsboltsbombsbondsbonedbonesboneybongobongsbonnybonusbooedbooksboomsboonsboorsbootsbootyboozeboozyboraxboredborerboresborneboronbosombossybosunbotchboughboutsbowedbowelbowerbowlsboxedboxenboxerboxesbozosbracebractbradsbragsbraidbrashbrassbratsbravobrawlbrawnbraysbreedbrewsbriarbribebrierbrigsbrimsbrinebrinkbrinybroilbroodbrothbrowsbruinbruntbruskbrutebucksbudgebuffsbuggybuglebulbsbulgebulgybulksbulkybullsbullybumpsbumpybungsbunksbunnybuntsbuoysburgsburkaburlyburnsburntburpsburroburrsbusbybusedbusesbushybustsbutchbuttebuxombylawbytesbywaycabalcabbycacaocachecacticaddycadetcadgecadrecagedcagescageycairncakedcakescalfscalifcalkscallscalmscalvecalyxcameocampscampycanalcanedcanescannycanoncantocantscapedcapercapescaponcaratcarbscardscaredcarescaretcarolcaromcarpicarpscartscasedcasescaskscastecastscatercattycaulkcavedcavescavilcawedceasecededcedescellicellocellscentschadschafechaffchaoschapscharscharychasmchatscheatcheepchefschewschewychickchidechilechimechimpchinachinochinschipschitschivechockchokechompchopschorechowschuckchugschumpchumschurlchurnchutecigarciliacinchcircacitedcitescivetcivilclackclamsclangclankclansclapsclaspclawscleatclefscleftclewsclimeclingclinkclipscliptclodsclogsclompcloneclopsclotscloutclovecloysclubscluckcluedcluesclumpclungclunkcoalscoatscobracoccicockycodascodedcodescodexcoedscoifscoilscoinscokedcokescolascoldscoliccoloncoltscomascombocombscomercomescomfycommacompoconchcondoconescongaconicconkscooedcookscookycoolscoopscootscopedcopescopracopsecordscoredcorescorkscormscornscornycorpscostscotescoughcoupecoupscovencovescovetcoveycowedcowercowlscoyercoylycozencrabscragscrampcramscrankcrapecrasscravecrawscrayscrazecreakcredocreedcreelcreepcrepecreptcresscrewscribscrickcriedcriercriescrimecrimpcroakcrocicrockcronecronycrookcrooncropscroupcrowscrudecruelcruetcryptcubedcubescubiccubitcuffscuingcullscultscumincupidcurbscurdscuredcurercurescuriecuriocurlscurlycurrycursecurstcurvycushycuspscutercutupcyniccystsczarsdachadaddydadosdaffydalesdallydamesdamnsdampsdandydareddaresdarnsdartsdateddatesdatumdaubsdauntdavitdawnsdazeddazesdealsdeansdearsdeathdebardebitdebtsdebugdebutdecafdecaydecksdecoydecrydeedsdeemsdeepsdeersdeferdeicedeifydeigndeismdeitydelisdellsdeltadelvedemondemosdemurdenimdentsdepotderbydesksdeterdetoxdeucedevildhotidialsdiceddicesdiceydickydictadietsdiffsdigitdikeddikesdillsdillydimerdimesdimlydineddinesdingodingsdingydinkydiodedirerdirgedirksdirtydiscodiscsdisksditchdittodittydivandivasdiveddiverdivesdivotdivvydjinndocksdodgydodosdoersdoffsdoggydogiedogmadoilydoleddolesdollsdollydoltsdomeddomesdonordoomsdoorsdopeddopesdopeydorksdorkydormsdoseddosesdoteddotesdottydousedovesdowdydoweldownsdownydowrydowsedoyendozeddozesdrabsdragsdrakedramsdrawldrawsdraysdreaddregsdrierdriesdrilydripsdroiddrolldronedrooldroopdropsdrossdrowndrubsdrugsdruiddrumsdrunkdryaddryerdrylyducalducatduchyducksductsdudeddudesduelsduetsdukesdullsdullydummydumpsdumpyduncedunesdungsdunksdunnodupeddupesduskydustsduvetdwarfdweebdweltdyersdyingdykedearlsearnseasedeaseseateneatereavesebbedebonyechosedemaedgededgeredgesedictedifyeditseerieeggedegreteiderejectekingelateelegyelfinelideelopeeludeelvesemailembedemberemceeemendemeryemirsemitsemojiemoteenactendedendowendueenemaenemyennuienrolensueenureenvoyepicsepochepoxyequiperaseerecterodeerrederuptesteretherethicethoseurosevadeevensevictevilsevokeewersexaltexamsexcelexecsexertexileexitsexpelexposextolexudeexulteyingfacedfacesfacetfactsfadedfadesfailsfairsfakedfakerfakesfakirfallsfamedfangsfannyfarcefaredfaresfarmsfastsfatalfatedfatesfattyfaultfaunafaunsfawnsfaxedfaxesfazedfazesfearsfeatsfecalfeedsfeelsfeignfeintfellsfelonfeltsfemurfendsferalfernsfestsfetalfetedfetidfetusfeudsfewerfezesfiatsfichefiefsfiendfieryfifesfightfilchfiledfilesfiletfillsfillyfilmsfilmyfilthfinchfindsfinedfinerfinesfinisfinksfinnyfiordfiredfiresfirmsfirthfishyfistsfitlyfiverfivesfixedfixerfixesfizzyfjordflackflagsflailflairflakyflankflapsflareflaskflatsflawsflaysfleasfleckfleesfleshflickfliedflierfliesflingflintflipsflirtflitsfloesflogsflopsfloraflossfloutflowsflubsfluesflukeflukyflumeflungflunkflushflybyflyerfoalsfoamsfoamyfocalfogeyfoggyfoilsfoistfoldsfoliofolksfollyfondufontsfoodsfoolsfootsforayfordsforesforgoforksformsfortefortsforumfoulsfountfoursfowlsfoxedfoxesfoyerfragsfrailfrancfrankfratsfraudfraysfreakfreedfreerfreesfretsfriarfrierfriesfrillfriskfrizzfrockfrogsfrondfrothfrownfrozefrumpfryerfuelsfuguefullsfumedfumesfundsfungifunksfunkyfurlsfurorfurryfurzefusedfusesfussyfustyfutonfuzedfuzesgabbygablegaffegaffsgagedgagesgailygainsgaitsgalasgalesgallsgamedgamergamesgameygamingammagamutgangsgapedgapesgarbsgasesgaspsgassygatedgatesgaudygaugegauntgauzegauzygavelgawksgawkygayergaylygazedgazergazesgearsgeckogeeksgeekygeesegeldsgelidgenesgeniegeniigenregentsgenusgeodegermsgetupghostghoulgibedgibesgiddygiftsgildsgillsgiltsgimmegimpygipsygirdsgirlsgirthgirtsgismogivesgizmogladsglandglaregleanglensglintglitzgloatglobsgloomglossglowsgluedgluesglueyglutsglyphgnarlgnashgnatsgnawngnawsgnomegoadsgoalsgoatsgodlygofergoldsgolfsgollygonadgonergongsgonnagonzogoodsgoodygooeygoofsgoofygoonsgoosegoredgoresgorgegorpsgorsegottagougegourdgoutygownsgrabsgradsgraftgrailgramsgrategravegravygraysgrazegrebegreedgreysgridsgriefgrimegrimygrinsgripegripsgristgritsgroangroingroksgropegrossgroutgrowlgrowsgrubsgruelgruesgruffgruntguanoguavaguildguileguiltguisegulaggulchgulfsgullsgullygulpsgumbogummygunnyguppygurusgushygustogustsgustygutsyguyedgybedgybesgypsygyroshackshaftshaikuhailshairshairyhakeshaledhalerhaleshallshalonhaloshaltshalvehandshangshankshankyhardyharedharemharesharksharmsharpsharpyharryhartshaspshatedhaterhateshaulshaunthavenhaveshavochawedhawkshayedhazedhazelhazesheadsheadyhealsheapshearsheathheatsheaveheedsheelsheftsheftyheirsheisthelixhelmshelothelpshencehennaherbsherdsheronheroshertzhewedhewerhexedhexeshickshidedhideshighshikedhikerhikeshillshillyhiltshindshingehingshintshippohippyhiredhireshitchhivedhiveshoagyhoardhoaryhoboshockshoganhoisthokeyhokumholdsholedholeshollyhomedhomerhomeshomeyhomiehonedhoneshonkshoochhoodshooeyhoofshookshookyhoopshootshopedhopeshordehornshorsyhosedhoseshostshotlyhourshovelhowdyhowlshubbyhuffshuffyhugerhulashulkshullshumidhumpshumushunchhunkshuntshurlshurtshuskshuskyhussyhutchhydrahyenahyinghymenhymnshypedhyperhypeshyposiambsiciericilyicingiconsideasidiomidiotidledidleridlesidolsidyllidylsiglooikonsillusimamsimbedimbueimpelimplyinaneinaptinboxincedincurindueineptinertinferinfixingotinkedinlayinletinsetintelinterintroinureiotasirateirkedironsislesisletitchyitemsiviesjabotjacksjadedjadesjailsjambsjapanjapedjapesjauntjawedjazzyjeansjeepsjeersjehadjellojellsjerksjerkyjestsjettyjibedjibesjiffyjihadjiltsjimmyjinnijinnsjivedjivesjocksjohnsjoinsjoistjokedjokerjokesjoltsjoulejoustjowlsjoyedjulepjumpsjuncojunksjunkyjuntajurorkabobkapokkaputkaratkarmakazookebabkebobkeelskeenskeepsketchkeyedkhakikhanskickskickykiddokiddykillskilnskiloskiltskindakindskingskinkskitedkiteskittykiwisklugeklutzknavekneadkneedkneesknellknifeknitsknobsknollknotsknowskoanskookskookykopekkronekudoskudzulabialacedlaceslacksladedladenladeslagerlairslaitylakeslamaslambslamedlamerlameslampslandslaneslankylapellapselarchlardslargolarkslarvalasedlaseslassolastslatexlathelathslattelaudslawnslaxerlaxlylazedlazesleachleadsleafsleafyleaksleakyleansleapsleaptleashleechleeksleersleeryleftsleftyleggylegitlemmalemmelemurlendsleperletupleveeliarslibellicitlicksliegeliensliferliftslikedlikenlikerlikesliltslimbolimbslimedlimeslimnslimoslimpslinedlinerlineslingolinkslintslionslipidliraslislelispslistsliterlithelivedlivenliverliveslividllanoloadsloafsloamyloansloathlobbylobedlobeslockslocuslodesloftsloftylogesloginlogonlogosloinslollslonerlongslooksloomsloonsloonyloopsloopylootslopedlopeslordslorryloserloseslottolotuslouselousyloutslovedloverloveslowedlowlyloxesluauslubedlubeslucidlucksluckylucrelullslumpslumpylungelungslupinlupuslurchluredluresluridlurkslustslustyluteslyinglymphlynchlyreslyricmacawmacedmacesmachomacromadammadlymagmamaidsmailsmaimsmainsmaizemakesmalesmallsmaltsmamasmambomammamanesmangamangemangymaniamanicmanlymannamanormansemaresmariamarksmartsmasksmasonmastsmatedmatesmattemattsmatzomaulsmauvemavenmavinmaxedmaxesmaximmazesmealsmealymeansmeatsmeatymeccamedicmeetsmeldsmeltsmemesmemosmendsmenusmeowsmeresmesasmessymetedmetesmetromewedmewlsmiaowmicramiddymidgemidstmiensmiffsmikedmikesmilchmilermilesmilksmilkymillsmimedmimesmimicmincemindsminedminerminesminimminisminksmintsmintymiredmiresmirthmisdomisermistsmistymitermitesmittsmixermixesmoansmoatsmochamocksmodalmodemmodesmogulmoiremolarmoldsmoldymolesmollsmoltsmommamommymonksmoochmoodsmoodymooedmoonsmoorsmootsmopedmopesmoraymoresmornsmoronmoseymossymotelmotesmothsmotifmottomoundmournmousymovedmovermovesmowedmowermucksmuckymucusmuffsmuftimuggymulchmulesmullsmultimummymumpsmunchmuralmurksmurkymusedmusesmushymuskymussymustsmustymutedmutermutesmuttsmynahmynasmyrrhmythsnabobnacrenadirnaiadnailsnaivenakednamednamesnannynapesnappynarcsnarksnasalnastynatalnattynavelnavesnearsneathnecksneedsneedyneighnerdsnerdynervynestsnewelnewernewsynewtsnexusnicernichenicksnieceniftynimbininesninjaninnynippyniternitesnixednixesnoblynodalnoddynodesnoelsnoisynomadnoncenooksnoosenormsnosednosesnoseynotednotesnounsnovaenovasnowaynudernudesnudgenukednukesnullsnumbsnuttynymphoakenoakumoaredoasesoatenoathsobeseobeysobitsoboesocherochreoctaloctetodderoddlyodiumodorsoffaloffedogledoglesogresoiledoinksokaysokrasoldenolderoldieomegaomensomitsonsetoozedoozesopalsopensopineopiumoptedopticoralsorateosieroustsoutdooutedoutgoovalsovaryovensoversovertovoidovuleowingowletownedoxbowoxideozonepacedpacespackspactspaddypadrepaeanpaganpagedpagerpagespailspainspairspaledpalerpalespallspalmspalmypalsypanespangspanicpantspantypapalpapaspapawparchparedparesparkaparksparryparsepartspashapastspastypatespathspatiopatsypattypavedpavespawedpawlspawnspayedpayeepayerpeakspealspearspeasepecanpeckspeekspeelspeepspeerspeevepekoepeltspenalpencependspenespeonspeonypeppyperilperksperkypermspeskypesospestspeterpettypeweephagephasephialphishphloxphonyphylapickspickypierspietypiggypigmypiingpikedpikerpikespilafpilaupilawpiledpilespillspinedpinespingspinkspinkypintopintspinuppiouspipedpiperpipespipitpiquepithypitonpivotpixieplaitplankplansplayspleadpleaspleatpliedpliesplodsplonkplopsplotsplowsploysplugsplumpplumsplunkpoachpockspodiapoemspoesypoetspoisepokedpokerpokespokeypoledpolespoliopolkapollspolyppondsponespoochpoohspoolspoopspopespoppapoppyporedporesportsposedposerposespositpossepostspottypourspoutspoxesprankprateprawnprayspreenprepspreysprickpricypriedpriesprigsprimppriorprismprivyprizeprodsprofspromopromsproneprongpropsproseprosyprowlprowsproxyprudepsalmpshawpsychpubicpuckspudgypuffspuffypukedpukespullspulpspulpypumaspumpspunkspuntspupaepupalpupaspureepurerpurgepurlspurrspushyputtsputtypygmypylonpyrespyxesquadsquaffquakequalmquarkquartquashquasiquaysquellqueuequidsquillquinequipsquirequitsquoitquotaquothrabbirabidracedracerracesracksradiiradonraftsragasragedragesraidsrailsrainsrajahrajasrakedrakesrampsrandyrangyranksrantsraredrarerraresraspsraspyratedratesrattyravedravelravenravesrawerrayonrazedrazesrazorreadsrealsreamsreapsrearmrearsrebusrebutrecaprectarecurredidreedsreedyreefsreeksreelsreeverefitregalrehabreinsrelicremitrenalrendsrentsreorgrepayrepelreranrerunresetresinrestsretchretryreuserevelrevuerheasrheumrhinoricedricesricksridesriferriffsrifleriftsrigidrigorriledrilesrillsrimedrimesrindsringsrinksriotsriperriserrisesrisksriskyritesritzyrivalrivenrivetroachroadsroamsroansroarsrobedrobesrocksrodeorogerrogueroilsrolesrollsromanrompsroodsroofsrooksroomsroomyroostrootsropedropesrosesrosinrotorrougerouseroutsrovedroverrovesrowdyrowedrowelrowerrubesrubleruddyruderruffsruingruinsruledrulesrumbarummyrumpsrunesrungsrunicrunnyruntsrupeerusesrusksrustssabersablesabresackssadessadlysafersafessagassagersagessahibsailssaintsaithsalessallysalonsalsasaltssaltysalvesalvosambasamessandssanersappysareesarissassysataysatedsatessatinsatyrsaucysaunasavedsaversavessavorsavvysawedsaxesscabsscadsscaldscalpscalyscampscamsscansscantscarescarsscaryscatsschwascionscoffscoldsconescootscornscourscowlscowsscramscrewscripscrodscubascudsscuffscullscumsscurfsealsseamsseamysearsseatssectssedansedgeseedsseedyseeksseemsseepsseerssegueseizesellssemissendssennasensesepalsepiaseptasererserfssergeserumserveservosetupseversewedsewershackshadsshaftshagsshahsshakyshaleshaltshameshamsshankshardshavesheafshearshedssheensheersheiksherdshiedshiesshillshimsshinsshipsshireshirkshirrshlepshoalshoedshoesshoonshoosshootshopsshornshotsshoveshowsshowyshredshrewshrugshtikshuckshunsshuntshushshutsshyershylysibylsickssidedsidessidlesiegesievesiftssighssigmasignssilkssillssilossiltssinewsingesingssinkssinussiredsirensiressirupsisalsisessissysitarsitedsitessixessizedsizersizesskeetskeinskewsskidsskiedskierskiesskiffskimpskimsskinsskipsskitsskulkskullskunkskyedslabsslackslagsslainslakeslamsslangslantslapsslashslatsslayssledssleeksleetsleptslewsslickslierslilyslimeslimsslimyslingslinkslipsslitsslobssloesslogssloopslopssloshslothslotsslowssluedsluesslugsslumpslumsslungslunkslurpslursslushslyerslylysmacksmashsmearsmeltsmirksmitesmithsmocksmokysmotesmurfsmutssnafusnagssnakesnakysnapssnaresnarksnarlsneersnidesniffsnipesnipssnitssnobssnoopsnootsnoresnortsnotssnoutsnowssnubssnucksnuffsnugssoakssoapssoapysoarssobersockssodassofassoftysoggysoilssoledsolessolossonarsongssonicsonnysoothsootysoppysorersoressortasortssoughsoulssoupssoupysourssousesowedsowerspacyspadespakespamsspankspanssparsspasmspatespatsspawnspaysspearspeckspecsspeltspermspewsspiedspielspiesspikespikyspiltspinsspinyspirespitespitssplatsplaysplitspoilspoofspookspoolspoorsporespotsspoutspratspreesprigspudsspumespunkspurnspursspurtsquabsquatsquawsquidstabsstagsstaidstalkstankstaphstarkstarsstashstatsstavestayssteadsteakstealsteedsteinstemsstentstepsstewsstiesstiffstilestiltstinkstintstirsstoatstoicstokestolestompstonystoopstopsstorkstowsstrapstrepstrewstropstrumstrutstubsstudsstumpstungstunkstunsstuntstyesstylisuavesuckssudsysuedesuingsuitssulkssulkysullysumacsumpssunupsurersurfssurlysushiswabsswagsswainswamiswankswansswapsswardswashswathswatsswaysswearsweatswellswigsswillswimsswineswipeswishswoonswoopswopssworeswornswungsylphsynchsyncssynodtabbytabootabustacittackstackytacostaffytailstainttakertakestalestalkstallytalontamedtamertamestampstangstangytankstansytapedtapertapestapirtardytaredtarestarostarottarpstarrytartstasertaskstattytaunttaupetawnytaxedtaxestaxisteakstealsteamstearstearyteaseteatstechsteemsteensteenytelextellstempitempstempttendstenettenontenortensetentstepeetepidtermsternsterryterseteststestytextsthawstheesthefttheirthesethetathiefthighthinethinsthongthousthrobthroethrumthudsthugsthumpthunkthymethymitiaratibiatickstidedtidestierstiffstikestildetiledtilestillstiltstimedtimestimidtinestingetingstinnytintstipistipsytirestirostitantithetizzytoadstoadytoddytoffytogaetogastoilstokedtokestollstombstomestonaltonedtonertonestongstonictonnetoolstootstopaztoquetorsitorsotortetortstorustotedtotemtotestourstoutstowedtownstoxictoxintoyedtracttramptramstranstrapstrashtrawltraystreadtreastreedtreestrekstresstriadtricetriestriketrilltrimstriostripetripstritetrolltromptronstropetrothtrotstroystrucetruedtruertruestrumptrusstrysttsarstubastubbytubedtubertubestuckstuftstulletumidtummytumortunastunedtunertunestunictunnyturfsturnstuskstutustuxestwaintwangtweaktweedtweettwerktwerptwigstwilltwinstwitstyingtykestypedtypestypostyrostzarsudderulcerulnaeulnasumbelumberumiakumpedunbaruncutundidundueunfitunifyunitsunmanunpinunsayunsetuntieunwedunzipupenduppedurgedurgesurineusersusherusingusurpusuryuteriuvulavacuavaguevalesvaletvalorvampsvanesvapedvapesvapidvasesvastsvauntveepsveersveganveilsveinsveldsveldtvenalvendsvenomventsvenueverbsvergevervevestsvetchvexedvexesvialsviandvibesvicarvicedvicesviewsvigilvilervillavinesviolsviperviralvireovirusvisasvisedvisesvisorvistavivasvixenvizorvodkavoguevoidsvoilevolesvoltsvomitvotedvotesvouchvowedvowelvyingwackowackswackywadedwaderwadeswadiswaftswagedwagerwageswaifswailswaitswaivewakedwakenwakeswaldowaledwaleswalkswallswaltzwandswanedwaneswanlywannawantswardswareswarmswarnswarpswartswartywaspswastewattswavedwaverwaveswaxedwaxenwaxeswealsweanswearsweedsweedyweeksweepsweepyweestweftsweirdweirswelchweldswellswelshweltswenchwendswetlywhackwhamswharfwhatswhealwhelkwhelpwhenswhetswhiffwhimswhinewhinywhipswhirrwhirswhiskwhistwhitswhizzwhoopwhorlwickswidenwidowwidthwieldwightwikiswildswiledwileswillswiltswimpswimpywincewinchwindswinedwineswingswinkswinoswipedwiperwipeswiredwireswiserwiseswispswispywitchwiveswizeswokenwolfswombswomenwonkywoodswoodywooedwooerwoofswoolywoozywordswordyworkswormswormyworseworstwoundwowedwrackwrapswraptwrathwreakwreckwrenswrestwrierwringwritswrongwrothwrungwryerwrylyxenonxylemyacksyahooyanksyardsyarnsyawedyawlsyawnsyeahsyearsyellsyelpsyesesyocksyodelyoginyogisyokedyokelyokesyolksyoursyowlsyuccayucksyuckyyummyyuppyzebuszeroszestszilchzincszingszippyzombizonalzonedzoneszooms'.toUpperCase();
  var VALID = {};
  (function () {
    var i;
    for (i = 0; i < ANSWERS.length; i++) VALID[ANSWERS[i]] = 1;
    for (i = 0; i < EXTRA.length; i += 5) VALID[EXTRA.substr(i, 5)] = 1;
  })();

  var ROWS = 6, COLS = 5, ROUND_TIME = 180;
  var FLIP = 0.34, STAGGER = 0.2, REVEAL_TOTAL = STAGGER * 4 + FLIP;
  var INK = '#2B2542', CORAL = '#F2644A', TEAL = '#1FB8A6', PAPER = '#F3E7D2';
  var SERIF = 'Georgia, "Times New Roman", serif';
  var FACE_TOP = ['#FFFDF5', '#494069', '#FF8769', '#44D6C2'];
  var FACE_BOT = ['#F7ECD8', '#2B2542', '#EC5538', '#13A392'];
  var LIP = ['#C7B289', '#151128', '#B03722', '#0A7368'];
  var TEXT = [INK, '#EFE8F4', '#FFF7EA', '#FCFFF8'];
  var POP = ['#2B2542', '#2B2542', '#D8472C', '#0B8779'];
  var CONFETTI = ['#1FB8A6', '#F2644A', '#2B2542', '#FFC94D', '#FFFDF5'];
  var KEY_ROWS = ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'];
  var OPENERS = ['STARE', 'CRANE', 'SLATE', 'TRAIN', 'HEART', 'STONE', 'LEARN', 'ROAST', 'PLANT', 'SHINE', 'BREAD', 'STEAM', 'OCEAN', 'RAISE', 'CLEAR', 'TRACE'];

  var L = null, bg = null, TG = null, KG = null;
  var answer, rows, curRow, typed, phase, timeLeft, score, dispScore, scoreBumpAt;
  var keyState, keyBumpAt, tealFound, letterFound;
  var now = 0, shakeAmp = 0, shakeX = 0, shakeY = 0;
  var toastText = '', toastAt = -9, toastRow = 0;
  var solvedRow = -1, stampAt = -1, stampHit = false, loseAt = -1, endAt = -1, ended = false, headline = '';
  var lastTick = 99, cursorAt = -9;
  var holds = {}, delHeld = false, delT = 0;
  var botScript = null, botI = 0, botT = 0;
  var scoreShown = -1, scoreStr = '0', timerShown = -1, timerStr = '3:00';
  var tmpUsed = [0, 0, 0, 0, 0], tmpRes = [0, 0, 0, 0, 0];

  var particles = [], popups = [], pi = 0, qi = 0;
  (function () {
    var i;
    for (i = 0; i < 150; i++) particles.push({ on: false, x: 0, y: 0, vx: 0, vy: 0, rot: 0, vr: 0, size: 0, life: 0, max: 1, color: '#fff', round: false });
    for (i = 0; i < 10; i++) popups.push({ on: false, text: '', x: 0, y: 0, t: 0, kind: 0, big: false });
  })();

  function serif(size) { return '900 ' + size + 'px ' + SERIF; }
  function lcg(a) {
    return function () {
      a |= 0; a = (a + 0x6d2b79f5) | 0;
      var t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function rr(c, x, y, w, h, r) {
    c.beginPath();
    if (r > w / 2) r = w / 2;
    if (r > h / 2) r = h / 2;
    if (r < 0) r = 0;
    if (c.roundRect) c.roundRect(x, y, w, h, r);
    else {
      c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r);
      c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath();
    }
  }
  function spaced(c, str, x, y, gap, align) {
    var i, w = 0;
    for (i = 0; i < str.length; i++) w += c.measureText(str[i]).width + (i ? gap : 0);
    var px = align === 'center' ? x - w / 2 : align === 'right' ? x - w : x;
    c.textAlign = 'left';
    for (i = 0; i < str.length; i++) {
      c.fillText(str[i], px, y);
      px += c.measureText(str[i]).width + gap;
    }
  }

  /* ---------- layout ---------- */

  function makeGrads(c, h) {
    var g = { face: [], gloss: [] }, i, gr;
    for (i = 0; i < 4; i++) {
      gr = c.createLinearGradient(0, -h / 2, 0, h / 2);
      gr.addColorStop(0, FACE_TOP[i]); gr.addColorStop(1, FACE_BOT[i]);
      g.face.push(gr);
    }
    for (i = 0; i < 4; i++) {
      gr = c.createLinearGradient(0, -h / 2, 0, 0);
      gr.addColorStop(0, 'rgba(255,255,255,' + (i === 1 ? 0.2 : 0.34) + ')'); gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.gloss.push(gr);
    }
    return g;
  }

  function capHeight(c, font) {
    c.font = font;
    var m = c.measureText('H');
    return m.actualBoundingBoxAscent || parseFloat(font.split(' ')[1]) * 0.7;
  }

  function layout() {
    var W = D.W, H = D.H, c = D.ctx;
    if (!W || !H) return;
    var colW = Math.min(W, 520);
    var hudY = D.safe.top + 60;
    var limit = H - D.safe.bottom - 12;
    var boardMin = hudY + 50;
    var kSide = 5, kgap = colW >= 420 ? 6 : colW >= 380 ? 5 : 4.5, rowGap = 9, kedge = 4;
    var kw = (colW - 2 * kSide - 9 * kgap) / 10, wide0 = 1.5 * kw + 0.5 * kgap;
    var kh = 46;
    var pad = Math.round(colW * 0.036), gap = Math.max(5, Math.round(colW * 0.018)), lip = 5;
    var avail = limit - (3 * kh + 2 * rowGap + 2) - boardMin - 14;
    var tile = Math.floor(Math.min((colW - 2 * pad - 4 * gap) / 5, (avail - 5 * gap - lip) / 6));
    if (tile < 24) tile = 24;
    var bh = ROWS * tile + (ROWS - 1) * gap;
    var extra = avail - bh - lip;
    if (extra > 0) kh += Math.min(6, extra / 3);
    var kbH = 3 * kh + 2 * rowGap + 2;
    var kbTop = limit - kbH;
    var spare = kbTop - 14 - (boardMin + bh + lip);
    var bw = COLS * tile + (COLS - 1) * gap;
    L = {
      W: W, H: H, st: D.safe.top, sb: D.safe.bottom, hudY: hudY, hx: Math.min((W - bw) / 2, Math.max(pad, (W - 340) / 2)),
      tile: tile, gap: gap, lip: lip, rad: Math.round(tile * 0.2),
      bx: (W - bw) / 2, by: boardMin + Math.max(0, Math.min(spare * 0.4, 28)), bw: bw, bh: bh,
      kw: kw, kh: kh, kedge: kedge, kbTop: kbTop, kbBottom: limit, keys: [], keyIndex: {},
      tileFont: serif(Math.round(tile * 0.6)), keyFont: serif(Math.round(Math.min(kw * 0.56, 21))),
      tileCap: 0, keyCap: 0,
      fLabel: D.textFont(9.5, 800), fTimer: D.textFont(16, 800), fEnter: D.textFont(Math.min(10.5, wide0 * 0.2), 800),
      fToast: D.textFont(15, 700), fCard: D.textFont(10.5, 800), fScore: serif(30)
    };
    L.tileCap = capHeight(c, L.tileFont);
    L.keyCap = capHeight(c, L.keyFont);
    var kx0 = (W - colW) / 2 + kSide, r, i, row, x, y, wide = 1.5 * kw + 0.5 * kgap;
    for (r = 0; r < 3; r++) {
      row = KEY_ROWS[r];
      y = kbTop + r * (kh + rowGap);
      x = kx0 + (r === 1 ? (kw + kgap) / 2 : 0);
      if (r === 2) { L.keys.push({ k: 'ENTER', x: x, y: y, w: wide, h: kh, downAt: -9, held: 0 }); x += wide + kgap; }
      for (i = 0; i < row.length; i++) {
        L.keys.push({ k: row[i], x: x, y: y, w: kw, h: kh, downAt: -9, held: 0 });
        x += kw + kgap;
      }
      if (r === 2) L.keys.push({ k: 'DEL', x: x, y: y, w: wide, h: kh, downAt: -9, held: 0 });
    }
    for (i = 0; i < L.keys.length; i++) L.keyIndex[L.keys[i].k] = L.keys[i];
    TG = makeGrads(c, tile);
    KG = makeGrads(c, kh - kedge);
    buildBg();
  }

  function tileX(i) { return L.bx + i * (L.tile + L.gap) + L.tile / 2; }
  function tileY(r) { return L.by + r * (L.tile + L.gap) + L.tile / 2; }

  function buildBg() {
    var W = L.W, H = L.H, dpr = D.dpr || 1, i, r, x, y, t = L.tile, g;
    if (!bg) bg = document.createElement('canvas');
    bg.width = Math.round(W * dpr); bg.height = Math.round(H * dpr);
    var c = bg.getContext('2d');
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    g = c.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#F7EDDA'); g.addColorStop(1, '#EFE1C7');
    c.fillStyle = g; c.fillRect(0, 0, W, H);
    g = c.createRadialGradient(W / 2, H * 0.32, 10, W / 2, H * 0.32, H * 0.7);
    g.addColorStop(0, 'rgba(255,251,240,0.6)'); g.addColorStop(1, 'rgba(255,251,240,0)');
    c.fillStyle = g; c.fillRect(0, 0, W, H);
    var rnd = lcg(11);
    for (i = 0; i < 1100; i++) {
      c.fillStyle = i % 2 ? 'rgba(125,95,45,0.05)' : 'rgba(255,255,255,0.14)';
      c.fillRect(rnd() * W, rnd() * H, 1 + rnd() * 1.3, 1 + rnd() * 1.3);
    }
    for (r = 0; r < ROWS; r++) {
      y = L.by + r * (t + L.gap);
      g = c.createLinearGradient(0, y, 0, y + t);
      g.addColorStop(0, '#C6B28A'); g.addColorStop(0.22, '#D6C49F'); g.addColorStop(1, '#DECDA9');
      for (i = 0; i < COLS; i++) {
        x = L.bx + i * (t + L.gap);
        rr(c, x - 1.5, y - 1, t + 3, t + 3.5, L.rad + 1.5);
        c.fillStyle = 'rgba(255,252,242,0.9)'; c.fill();
        rr(c, x, y, t, t, L.rad);
        c.fillStyle = g; c.fill();
        rr(c, x + 0.5, y + 0.5, t - 1, t - 1, L.rad);
        c.strokeStyle = 'rgba(105,80,40,0.13)'; c.lineWidth = 1; c.stroke();
      }
    }
  }

  /* ---------- rules ---------- */

  function evaluate(g, a, out) {
    var i, j;
    for (i = 0; i < 5; i++) { out[i] = 1; tmpUsed[i] = 0; }
    for (i = 0; i < 5; i++) if (g[i] === a[i]) { out[i] = 3; tmpUsed[i] = 1; }
    for (i = 0; i < 5; i++) {
      if (out[i] === 3) continue;
      for (j = 0; j < 5; j++) if (!tmpUsed[j] && g[i] === a[j]) { out[i] = 2; tmpUsed[j] = 1; break; }
    }
  }
  function fbCode(g, a) {
    evaluate(g, a, tmpRes);
    return tmpRes[0] + tmpRes[1] * 4 + tmpRes[2] * 16 + tmpRes[3] * 64 + tmpRes[4] * 256;
  }

  function addScore(n) { score += n; scoreBumpAt = now; }

  function toast(text, row) { toastText = text; toastAt = now; toastRow = row; }

  function typeLetter(ch) {
    if (phase !== 'play') return;
    if (typed >= COLS) { rows[curRow].shakeAt = now; rows[curRow].shakeAmp = 3; return; }
    var row = rows[curRow];
    row.ch[typed] = ch; row.popT[typed] = now;
    typed++;
    cursorAt = now;
    D.tone({ freq: 430 + typed * 45, dur: 0.05, type: 'triangle', vol: 0.07 });
  }

  function backspace() {
    if (phase !== 'play' || typed === 0) return;
    typed--;
    rows[curRow].ch[typed] = '';
    cursorAt = now;
    D.tone({ freq: 300, dur: 0.05, type: 'triangle', vol: 0.06 });
  }

  function submit() {
    if (phase !== 'play') return;
    var row = rows[curRow];
    if (typed < COLS) {
      row.shakeAt = now; row.shakeAmp = 6; toast('Not enough letters', curRow);
      D.haptic('warning'); D.tone({ freq: 190, dur: 0.14, type: 'square', vol: 0.05 });
      return;
    }
    var g = row.ch.join('');
    if (!VALID[g]) {
      row.shakeAt = now; row.shakeAmp = 9; toast('Not a word', curRow);
      D.haptic('warning'); D.tone({ freq: 170, dur: 0.18, type: 'square', vol: 0.06, slide: 120 });
      return;
    }
    evaluate(g, answer, row.res);
    row.revealAt = now;
    row.solved = g === answer;
    if (row.solved) { phase = 'solved'; solvedRow = curRow; }
    else if (curRow === ROWS - 1) phase = 'lost';
    else { curRow++; typed = 0; cursorAt = now + REVEAL_TOTAL * 0.5; }
  }

  function pressKey(k) {
    if (phase !== 'play') return;
    D.haptic('select');
    if (k === 'ENTER') submit();
    else if (k === 'DEL') backspace();
    else typeLetter(k);
  }

  function tap(k) {
    var key = L.keyIndex[k];
    if (key) key.downAt = now;
    pressKey(k);
  }

  function onFlip(r, i) {
    var row = rows[r], res = row.res[i], ch = row.ch[i], gain = 0, n, x = tileX(i), y = tileY(r);
    D.haptic('light');
    D.tone({ freq: res === 3 ? 660 + i * 40 : res === 2 ? 520 + i * 20 : 260, dur: 0.09, type: res === 1 ? 'sine' : 'triangle', vol: 0.08 });
    if ((keyState[ch] || 0) < res) { keyState[ch] = res; keyBumpAt[ch] = now; }
    if (res === 3) {
      if (!tealFound[i]) { tealFound[i] = 1; gain = 20; }
      letterFound[ch] = 1;
    } else if (res === 2 && !letterFound[ch]) { letterFound[ch] = 1; gain = 10; }
    if (gain) { addScore(gain); popup('+' + gain, x, y - L.tile / 2 + 9, res, false); }
    n = res === 3 ? 8 : res === 2 ? 5 : 0;
    while (n-- > 0) spark(x + (Math.random() - 0.5) * L.tile * 0.7, y, res === 3 ? TEAL : CORAL, 150, false);
  }

  function onSolved(r) {
    var tries = r + 1, bonus = 200 + (ROWS - tries) * 100 + Math.ceil(timeLeft) * 2, i;
    rows[r].bounceAt = now;
    stampAt = now + 0.34; stampHit = false;
    addScore(bonus);
    D.ctx.font = L.fScore;
    popup('+' + bonus, L.hx + D.ctx.measureText(String(score)).width + 12, L.hudY + 34, 3, true);
    D.haptic('success');
    D.tone({ freq: 523, dur: 0.12, type: 'triangle', vol: 0.1 });
    D.tone({ freq: 784, dur: 0.22, type: 'triangle', vol: 0.1, slide: 1046 });
    shakeAmp = 5;
    for (i = 0; i < 70; i++) spark(L.bx + Math.random() * L.bw, tileY(r), CONFETTI[i % CONFETTI.length], 420, true);
    headline = 'Solved in ' + tries;
    endAt = now + (D.clip ? 2 : 1.35);
  }

  function onLost() {
    loseAt = now;
    D.haptic('error');
    D.tone({ freq: 220, dur: 0.4, type: 'sawtooth', vol: 0.08, slide: 90 });
    shakeAmp = 11;
    headline = 'The word was ' + answer;
    endAt = now + (D.clip ? 2 : 1.5);
  }

  function spark(x, y, color, speed, confetti) {
    var p = particles[pi]; pi = (pi + 1) % particles.length;
    var a = confetti ? -Math.PI / 2 + (Math.random() - 0.5) * 2.4 : Math.random() * Math.PI * 2;
    var v = speed * (0.35 + Math.random() * 0.75);
    p.on = true; p.x = x; p.y = y;
    p.vx = Math.cos(a) * v; p.vy = Math.sin(a) * v - (confetti ? 120 : 60);
    p.rot = Math.random() * 6; p.vr = (Math.random() - 0.5) * 14;
    p.size = confetti ? 5 + Math.random() * 5 : 3 + Math.random() * 3.5;
    p.life = 0; p.max = confetti ? 1.1 + Math.random() * 0.7 : 0.45 + Math.random() * 0.3;
    p.color = color; p.round = !confetti && Math.random() < 0.5;
  }

  function popup(text, x, y, kind, big) {
    var p = popups[qi]; qi = (qi + 1) % popups.length;
    p.on = true; p.text = text; p.x = x; p.y = y; p.t = 0; p.kind = kind; p.big = big;
  }

  /* ---------- bot ---------- */

  function planGuesses(rnd) {
    var cands = ANSWERS, out = [], alts = [], n, i, j, c, code, next, freq, best, s, ch, seen, top;
    var oi = Math.floor(rnd() * OPENERS.length), g = OPENERS[oi];
    if (g === answer) g = OPENERS[(oi + 1) % OPENERS.length];
    for (n = 0; n < ROWS; n++) {
      out.push(g);
      if (g === answer) break;
      code = fbCode(g, answer);
      next = [];
      for (i = 0; i < cands.length; i++) { c = cands[i]; if (c !== g && fbCode(g, c) === code) next.push(c); }
      cands = next;
      freq = {};
      for (i = 0; i < cands.length; i++) {
        c = cands[i];
        for (j = 0; j < 5; j++) if (c.indexOf(c[j]) === j) freq[c[j]] = (freq[c[j]] || 0) + 1;
      }
      best = [];
      for (i = 0; i < cands.length; i++) {
        c = cands[i]; s = 0;
        for (j = 0; j < 5; j++) if (c.indexOf(c[j]) === j) s += freq[c[j]];
        best.push({ w: c, s: s + rnd() * 0.5 });
      }
      best.sort(function (a, b) { return b.s - a.s; });
      top = Math.min(3, best.length);
      i = Math.floor(rnd() * top);
      g = best[i].w;
      alts.push(best.length > 1 ? best[i === 0 ? 1 : 0].w : null);
    }
    return { guesses: out, alts: alts, solved: out[out.length - 1] === answer };
  }

  function neighbour(ch, rnd) {
    var r, i, row;
    for (r = 0; r < 3; r++) {
      row = KEY_ROWS[r]; i = row.indexOf(ch);
      if (i >= 0) return i === 0 ? row[1] : i === row.length - 1 ? row[i - 1] : row[i + (rnd() < 0.5 ? 1 : -1)];
    }
    return ch;
  }

  function planBot(seed) {
    var rnd = lcg(seed * 7919 + 17), plan = null, p, t, s = [], g, j, w, alt, n, first, think, typo, d, mind, total = 0, slack, N;
    for (t = 0; t < 14; t++) {
      p = planGuesses(rnd);
      if (!p.solved) continue;
      if (!plan || Math.abs(p.guesses.length - 4) < Math.abs(plan.guesses.length - 4)) plan = p;
      if (p.guesses.length >= 3 && p.guesses.length <= 5 && (p.guesses.length === 4 || rnd() < (p.guesses.length === 5 ? 0.8 : 0.4))) { plan = p; break; }
    }
    if (!plan) { plan = p; plan.guesses[plan.guesses.length - 1] = answer; }
    N = plan.guesses.length;
    mind = N >= 3 ? 1 + Math.floor(rnd() * (N - 1)) : -1;
    function push(k, delay, kind) {
      s.push({ k: k, d: delay + (first ? think : 0), kind: first ? 1 : kind || 0 });
      first = false;
    }
    for (g = 0; g < N; g++) {
      w = plan.guesses[g];
      first = true;
      think = g === 0 ? 0.8 + rnd() * 0.4 : REVEAL_TOTAL + 0.9 + rnd() * 0.8;
      alt = g > 0 ? plan.alts[g - 1] : null;
      d = 0;
      if (g === mind && alt && alt !== w) {
        n = 3 + Math.floor(rnd() * 3);
        for (j = 0; j < n; j++) push(alt[j], 0.12 + rnd() * 0.14);
        for (j = 0; j < n; j++) push('DEL', j === 0 ? 0.55 + rnd() * 0.35 : 0.09 + rnd() * 0.05);
        d = 0.3;
      }
      typo = rnd() < 0.28 ? 1 + Math.floor(rnd() * 4) : -1;
      for (j = 0; j < 5; j++) {
        d += 0.12 + rnd() * 0.14;
        if (j === typo) {
          push(neighbour(w[j], rnd), d);
          push('DEL', 0.3 + rnd() * 0.14);
          push(w[j], 0.17 + rnd() * 0.08);
        } else push(w[j], d);
        d = 0;
      }
      push('ENTER', 0.5 + rnd() * 0.35, 2);
    }
    for (j = 0; j < s.length; j++) total += s[j].d;
    total += REVEAL_TOTAL + 2;
    slack = 11.9 + 4 * N - total;
    if (slack > 0) for (j = 0; j < s.length; j++) {
      if (s[j].kind === 1) s[j].d += slack * 0.62 / N;
      else if (s[j].kind === 2) s[j].d += slack * 0.38 / N;
    }
    botScript = s; botI = 0; botT = 0;
  }

  /* ---------- drawing ---------- */

  function drawRaised(c, s, kind, letter) {
    var h = s / 2, r = L.rad;
    rr(c, -h, -h + L.lip, s, s, r); c.fillStyle = LIP[kind]; c.fill();
    rr(c, -h, -h, s, s, r); c.fillStyle = TG.face[kind]; c.fill();
    rr(c, -h + 3, -h + 3, s - 6, s * 0.46, r - 2.5); c.fillStyle = TG.gloss[kind]; c.fill();
    if (letter) {
      c.font = L.tileFont; c.textAlign = 'center'; c.textBaseline = 'alphabetic';
      c.fillStyle = LIP[kind]; c.globalAlpha = 0.55; c.fillText(letter, 0, L.tileCap / 2 + 2.5); c.globalAlpha = 1;
      c.fillStyle = TEXT[kind]; c.fillText(letter, 0, L.tileCap / 2);
    }
  }

  function drawTyped(c, s, letter) {
    var h = s / 2, r = L.rad;
    rr(c, -h, -h + L.lip, s, s, r); c.fillStyle = INK; c.fill();
    rr(c, -h + 1.5, -h + 1.5, s - 3, s - 3, r - 1); c.fillStyle = TG.face[0]; c.fill();
    c.lineWidth = 3; c.strokeStyle = INK; c.stroke();
    c.font = L.tileFont; c.textAlign = 'center'; c.textBaseline = 'alphabetic';
    c.fillStyle = INK; c.fillText(letter, 0, L.tileCap / 2);
  }

  function drawCursor(c, s) {
    var h = s / 2, r = L.rad, blink = 0.5 + 0.5 * Math.cos((now - cursorAt) * 5.2);
    rr(c, -h + 1.5, -h + 1.5, s - 3, s - 3, r - 1); c.fillStyle = '#FBF0E2'; c.fill();
    c.lineWidth = 3; c.strokeStyle = CORAL; c.stroke();
    c.globalAlpha = 0.15 + 0.85 * blink;
    rr(c, -s * 0.17, s * 0.24, s * 0.34, Math.max(3, s * 0.06), 2); c.fillStyle = CORAL; c.fill();
    c.globalAlpha = 1;
  }

  function drawBoard(c, state) {
    var pass, r, i, row, look, sx, sy, rot, dy, anim, p, q, tb, tp, k, dx, t = L.tile;
    for (pass = 0; pass < 2; pass++) {
      for (r = 0; r < ROWS; r++) {
        row = rows[r];
        dx = 0;
        tp = now - row.shakeAt;
        if (tp < 0.42) dx = Math.sin(tp * 44) * row.shakeAmp * (1 - tp / 0.42);
        for (i = 0; i < COLS; i++) {
          look = -1; sx = 1; sy = 1; rot = 0; dy = 0; anim = dx !== 0;
          if (row.revealAt >= 0) {
            p = (now - row.revealAt - i * STAGGER) / FLIP;
            if (p <= 0) look = 0;
            else if (p < 1) {
              anim = true;
              sy = Math.abs(Math.cos(p * Math.PI)); if (sy < 0.05) sy = 0.05;
              look = p < 0.5 ? 0 : row.res[i];
              dy = -Math.sin(p * Math.PI) * 4;
            } else {
              look = row.res[i];
              if (p < 1.45) { anim = true; q = Math.sin((p - 1) / 0.45 * Math.PI); sx = 1 + 0.08 * q; sy = 1 - 0.07 * q; }
            }
            if (row.bounceAt >= 0) {
              tb = now - row.bounceAt - i * 0.075;
              if (tb > 0 && tb < 0.5) {
                anim = true; q = Math.sin(tb / 0.5 * Math.PI);
                dy -= q * t * 0.36; sx *= 1 - 0.06 * q; sy *= 1 + 0.08 * q; rot = (i - 2) * 0.03 * q;
              } else if (tb >= 0.5 && tb < 0.72) {
                anim = true; q = Math.sin((tb - 0.5) / 0.22 * Math.PI);
                sx *= 1 + 0.09 * q; sy *= 1 - 0.1 * q; dy += q * t * 0.04;
              }
            }
          } else if (row.ch[i]) {
            look = 0;
            tp = now - row.popT[i];
            if (tp < 0.22) {
              anim = true; k = D.easeOutBack(tp / 0.22);
              sx = sy = 1.26 - 0.26 * k; rot = (i % 2 ? 1 : -1) * 0.11 * (1 - tp / 0.22); dy = -5 * (1 - tp / 0.22);
            }
          } else if (r === curRow && i === typed && phase === 'play' && state !== 'over') {
            look = 4;
            tp = now - cursorAt;
            if (tp >= 0 && tp < 0.14) { anim = true; sx = sy = 0.9 + 0.1 * (tp / 0.14); }
          }
          if (look < 0 || (anim ? 1 : 0) !== pass) continue;
          c.save();
          c.translate(tileX(i) + dx, tileY(r) + dy);
          if (rot) c.rotate(rot);
          if (sx !== 1 || sy !== 1) c.scale(sx, sy);
          if (look === 4) drawCursor(c, t);
          else if (look === 0) drawTyped(c, t, row.ch[i]);
          else drawRaised(c, t, look, row.ch[i]);
          c.restore();
        }
      }
    }
  }

  function drawKeys(c) {
    var i, key, st, down, e = L.kedge, fh = L.kh - e, off, w, tb, sc, single, full = typed === COLS && phase === 'play';
    for (i = 0; i < L.keys.length; i++) {
      key = L.keys[i];
      rr(c, key.x, key.y + e + 2, key.w, fh, 8);
      c.fillStyle = 'rgba(95,70,30,0.14)'; c.fill();
    }
    for (i = 0; i < L.keys.length; i++) {
      key = L.keys[i];
      single = key.k.length === 1;
      st = single ? keyState[key.k] || 0 : 0;
      down = key.held > 0 || now - key.downAt < 0.11;
      off = down ? e : 0;
      w = key.w;
      rr(c, key.x, key.y + e, w, fh, 8);
      c.fillStyle = LIP[st]; c.fill();
      c.save();
      c.translate(key.x + w / 2, key.y + off + fh / 2);
      if (single && st) {
        tb = now - (keyBumpAt[key.k] || -9);
        if (tb < 0.3) { sc = 1 + 0.16 * Math.sin(tb / 0.3 * Math.PI); c.scale(sc, sc); }
      }
      rr(c, -w / 2, -fh / 2, w, fh, 8);
      c.fillStyle = down && !st ? '#F3E7D0' : KG.face[st]; c.fill();
      if (st) { rr(c, -w / 2 + 2, -fh / 2 + 2, w - 4, fh * 0.42, 6); c.fillStyle = KG.gloss[st]; c.fill(); }
      else { c.lineWidth = 1; c.strokeStyle = 'rgba(150,120,70,0.28)'; rr(c, -w / 2 + 0.5, -fh / 2 + 0.5, w - 1, fh - 1, 7.5); c.stroke(); }
      if (single) {
        c.font = L.keyFont; c.textAlign = 'center'; c.textBaseline = 'alphabetic';
        c.fillStyle = TEXT[st]; c.fillText(key.k, 0, L.keyCap / 2);
      } else if (key.k === 'ENTER') {
        if (full) {
          c.globalAlpha = 0.55 + 0.45 * Math.sin(now * 7);
          c.lineWidth = 2.5; c.strokeStyle = CORAL; rr(c, -w / 2 + 2, -fh / 2 + 2, w - 4, fh - 4, 6.5); c.stroke();
          c.globalAlpha = 1;
        }
        c.font = L.fEnter; c.textBaseline = 'middle';
        c.fillStyle = full ? '#D8472C' : INK;
        spaced(c, 'ENTER', 0, 0.5, 0.9, 'center');
      } else {
        c.lineWidth = 1.9; c.strokeStyle = INK; c.lineJoin = 'round'; c.lineCap = 'round';
        c.beginPath();
        c.moveTo(-9, 0); c.lineTo(-3.5, -6.5); c.lineTo(9, -6.5); c.lineTo(9, 6.5); c.lineTo(-3.5, 6.5); c.closePath();
        c.moveTo(0.5, -2.6); c.lineTo(5.7, 2.6); c.moveTo(5.7, -2.6); c.lineTo(0.5, 2.6);
        c.stroke();
      }
      c.restore();
    }
  }

  function drawHud(c, state) {
    var W = L.W, y = L.hudY, x = L.hx + 1, s, t, tb, i, px, low, secs, m, ss, pw, ph, cx, row, col;
    c.font = L.fLabel; c.textBaseline = 'alphabetic';
    c.fillStyle = 'rgba(43,37,66,0.58)';
    spaced(c, 'SCORE', x, y + 9, 2.4, 'left');
    spaced(c, 'TRIES', W - x, y + 9, 2.4, 'right');
    s = Math.round(dispScore);
    if (s !== scoreShown) { scoreShown = s; scoreStr = String(s); }
    tb = now - scoreBumpAt;
    c.save();
    c.translate(x, y + 38);
    if (tb < 0.25) { t = 1 + 0.2 * Math.sin(tb / 0.25 * Math.PI); c.scale(t, t); }
    c.font = L.fScore; c.textAlign = 'left'; c.fillStyle = INK;
    c.fillText(scoreStr, -1, 0);
    c.restore();

    for (i = 0; i < ROWS; i++) {
      px = W - x - (ROWS - i) * 15 + 4;
      row = rows[i];
      rr(c, px, y + 20, 11, 11, 3.5);
      if (row.done) { c.fillStyle = row.solved ? TEAL : INK; c.fill(); }
      else if (i === curRow && phase === 'play') {
        c.fillStyle = '#FFF8EA'; c.fill(); c.lineWidth = 2; c.strokeStyle = CORAL; rr(c, px + 1, y + 21, 9, 9, 2.5); c.stroke();
      } else { c.fillStyle = '#D3C19B'; c.fill(); }
    }

    secs = Math.ceil(timeLeft); if (secs < 0) secs = 0;
    if (secs !== timerShown) { timerShown = secs; m = Math.floor(secs / 60); ss = secs % 60; timerStr = m + ':' + (ss < 10 ? '0' : '') + ss; }
    low = secs <= 30 && phase === 'play' && state === 'playing';
    pw = 86; ph = 30; cx = W / 2;
    c.save();
    c.translate(cx, y + 23);
    if (low && secs <= 10) { t = 1 + 0.1 * Math.max(0, 1 - (secs - timeLeft) * 4); c.scale(t, t); }
    col = low ? '#D8472C' : INK;
    rr(c, -pw / 2, -ph / 2 + 3, pw, ph, ph / 2); c.fillStyle = low ? '#A4311D' : '#151128'; c.fill();
    rr(c, -pw / 2, -ph / 2, pw, ph, ph / 2); c.fillStyle = col; c.fill();
    c.strokeStyle = '#FFF8EA'; c.lineWidth = 1.8; c.lineCap = 'round';
    c.beginPath(); c.arc(-24, 0, 7, 0, Math.PI * 2);
    c.moveTo(-24, -3.6); c.lineTo(-24, 0); c.lineTo(-21.4, 1.6);
    c.stroke();
    c.font = L.fTimer; c.textAlign = 'left'; c.textBaseline = 'middle'; c.fillStyle = '#FFF8EA';
    c.fillText(timerStr, -11, 1);
    c.restore();
  }

  function drawToast(c) {
    var t = now - toastAt, a, s, w, y;
    if (t < 0 || t > 1.35) return;
    a = t > 1.1 ? 1 - (t - 1.1) / 0.25 : 1;
    s = t < 0.16 ? D.easeOutBack(t / 0.16) : 1;
    y = tileY(toastRow) - L.tile / 2 - L.gap / 2;
    if (toastRow === 0) y = tileY(0) + L.tile / 2 + L.gap / 2;
    c.save();
    c.translate(L.W / 2, y); c.scale(s, s); c.globalAlpha = a;
    c.font = L.fToast;
    w = c.measureText(toastText).width + 34;
    rr(c, -w / 2, -17 + 3, w, 36, 18); c.fillStyle = '#151128'; c.fill();
    rr(c, -w / 2, -18, w, 36, 18); c.fillStyle = INK; c.fill();
    c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillStyle = '#FFF8EA';
    c.fillText(toastText, 0, 0.5);
    c.restore();
  }

  function drawHint(c) {
    var y = tileY(1) - L.tile * 0.06 + Math.sin(now * 2.6) * 2.5, w, text = 'TYPE A FIVE LETTER WORD', size = Math.max(11, Math.min(14, L.W * 0.034));
    c.font = serif(size);
    w = c.measureText(text).width + 22 * 1.0 + 20;
    rr(c, -w / 2 + L.W / 2, y - 17 + 3.5, w, 36, 18); c.fillStyle = INK; c.fill();
    rr(c, -w / 2 + L.W / 2 + 1.25, y - 18 + 1.25, w - 2.5, 33.5, 17); c.fillStyle = '#FFFFFF'; c.fill();
    c.lineWidth = 2.5; c.strokeStyle = INK; c.stroke();
    c.fillStyle = INK; c.textBaseline = 'middle';
    spaced(c, text, L.W / 2, y - 0.5, 1, 'center');
  }

  function drawStamp(c) {
    var t = now - stampAt, r = solvedRow, a, s, w, h, cy, fs;
    if (stampAt < 0 || t < 0) return;
    cy = r <= 3 ? tileY(r + 1) + (L.tile + L.gap) / 2 + L.lip : r === 4 ? tileY(5) + L.lip / 2 : tileY(3) + (L.tile + L.gap) / 2;
    a = Math.min(1, t / 0.12);
    s = t < 0.16 ? 2.5 - 1.5 * D.easeOut(t / 0.16) : 1 + 0.06 * Math.max(0, 1 - (t - 0.16) / 0.18) * Math.sin((t - 0.16) * 30);
    w = L.bw * 0.74; h = L.tile * 1.06; fs = Math.round(h * 0.58);
    c.save();
    c.translate(L.W / 2, cy); c.rotate(-0.16); c.scale(s, s);
    c.globalAlpha = a;
    rr(c, -w / 2, -h / 2, w, h, 12); c.fillStyle = 'rgba(250,241,224,0.93)'; c.fill();
    c.lineWidth = 5; c.strokeStyle = CORAL; c.stroke();
    rr(c, -w / 2 + 7.5, -h / 2 + 7.5, w - 15, h - 15, 6); c.lineWidth = 1.8; c.stroke();
    c.font = serif(fs); c.textBaseline = 'alphabetic'; c.fillStyle = CORAL;
    spaced(c, 'SOLVED', 1, fs * 0.355, fs * 0.09, 'center');
    c.restore();
  }

  function drawLoss(c) {
    var t = now - loseAt, s, w, h, i, ts, tx, p, sy, cy;
    if (loseAt < 0) return;
    s = t < 0.3 ? D.easeOutBack(t / 0.3) : 1;
    ts = Math.min(L.tile * 0.68, 50);
    w = ts * 5 + 4 * 5 + 36; h = ts + 62;
    cy = L.by + L.bh / 2;
    c.save();
    c.translate(L.W / 2, cy); c.rotate(-0.035); c.scale(s, s);
    c.globalAlpha = Math.min(1, t / 0.12);
    rr(c, -w / 2, -h / 2 + 6, w, h, 18); c.fillStyle = '#151128'; c.fill();
    rr(c, -w / 2, -h / 2, w, h, 18); c.fillStyle = INK; c.fill();
    c.lineWidth = 1.5; c.strokeStyle = 'rgba(255,248,234,0.16)'; rr(c, -w / 2 + 5, -h / 2 + 5, w - 10, h - 10, 14); c.stroke();
    c.font = L.fCard; c.textBaseline = 'alphabetic'; c.fillStyle = 'rgba(255,248,234,0.72)';
    spaced(c, 'THE WORD WAS', 0, -h / 2 + 25, 2.6, 'center');
    for (i = 0; i < 5; i++) {
      p = (t - 0.25 - i * 0.09) / 0.26;
      if (p <= 0) continue;
      sy = p < 1 ? D.easeOutBack(p) : 1;
      tx = (i - 2) * (ts + 5);
      c.save();
      c.translate(tx, 14); c.scale(ts / L.tile, ts / L.tile * sy);
      drawRaised(c, L.tile, 3, answer[i]);
      c.restore();
    }
    c.restore();
  }

  function drawParticles(c) {
    var i, p, a;
    for (i = 0; i < particles.length; i++) {
      p = particles[i];
      if (!p.on) continue;
      a = 1 - p.life / p.max;
      c.globalAlpha = a < 0.3 ? a / 0.3 : 1;
      c.fillStyle = p.color;
      if (p.round) { c.beginPath(); c.arc(p.x, p.y, p.size * 0.5, 0, Math.PI * 2); c.fill(); }
      else {
        c.save(); c.translate(p.x, p.y); c.rotate(p.rot);
        c.fillRect(-p.size / 2, -p.size * 0.32, p.size, p.size * 0.64);
        c.restore();
      }
    }
    c.globalAlpha = 1;
  }

  function drawPopups(c) {
    var i, p, k, size, s;
    for (i = 0; i < popups.length; i++) {
      p = popups[i];
      if (!p.on) continue;
      k = p.t / (p.big ? 1.5 : 0.85);
      size = p.big ? 21 : 19;
      s = p.t < 0.14 ? D.easeOutBack(p.t / 0.14) : 1;
      c.save();
      c.translate(p.x, p.y - (p.big ? 8 : 16) * D.easeOut(k));
      c.scale(s, s);
      c.globalAlpha = k > 0.7 ? Math.max(0, 1 - (k - 0.7) / 0.3) : 1;
      c.font = serif(size); c.textAlign = p.big ? 'left' : 'center'; c.textBaseline = 'alphabetic';
      c.lineJoin = 'round'; c.lineWidth = 5; c.strokeStyle = '#FFF8EA';
      c.strokeText(p.text, 0, 0);
      c.fillStyle = POP[p.kind]; c.fillText(p.text, 0, 0);
      c.restore();
    }
    c.globalAlpha = 1;
  }

  /* ---------- input ---------- */

  function keyAt(x, y) {
    var i, key, dx, dy, d, best = null, bd = 18;
    if (y < L.kbTop - 14) return null;
    for (i = 0; i < L.keys.length; i++) {
      key = L.keys[i];
      dx = Math.max(key.x - x, 0, x - key.x - key.w);
      dy = Math.max(key.y - y, 0, y - key.y - key.h);
      d = dx + dy;
      if (d < bd) { bd = d; best = key; }
    }
    return best;
  }

  function release(id) {
    var key = holds[id];
    if (!key) return;
    holds[id] = null;
    if (key.held > 0) key.held--;
    if (key.k === 'DEL') delHeld = false;
  }

  /* ---------- game ---------- */

  D.game({
    reset: function (seed) {
      var r, i, k;
      if (!L || L.W !== D.W || L.H !== D.H || L.st !== D.safe.top || L.sb !== D.safe.bottom) layout();
      answer = ANSWERS[Math.floor(D.rand() * ANSWERS.length)];
      rows = [];
      for (r = 0; r < ROWS; r++) {
        rows.push({ ch: ['', '', '', '', ''], res: [0, 0, 0, 0, 0], popT: [-9, -9, -9, -9, -9], revealAt: -1, flipped: 0, done: false, solved: false, shakeAt: -9, shakeAmp: 9, bounceAt: -1 });
      }
      curRow = 0; typed = 0; phase = 'play'; timeLeft = ROUND_TIME;
      score = 0; dispScore = 0; scoreBumpAt = -9;
      keyState = {}; keyBumpAt = {}; tealFound = [0, 0, 0, 0, 0]; letterFound = {};
      now = 0; shakeAmp = 0; shakeX = 0; shakeY = 0;
      toastAt = -9; solvedRow = -1; stampAt = -1; stampHit = false; loseAt = -1; endAt = -1; ended = false; headline = '';
      lastTick = 99; cursorAt = 0;
      holds = {}; delHeld = false; delT = 0;
      for (i = 0; i < L.keys.length; i++) { k = L.keys[i]; k.downAt = -9; k.held = 0; }
      for (i = 0; i < particles.length; i++) particles[i].on = false;
      for (i = 0; i < popups.length; i++) popups[i].on = false;
      botScript = null;
      if (D.clip) planBot(seed || 1);
    },

    start: function () { cursorAt = now; },

    resize: function () { layout(); },

    update: function (dt, state) {
      var r, row, i, p;
      if (L.st !== D.safe.top || L.sb !== D.safe.bottom) layout();
      now += dt;
      if (state === 'playing') {
        if (phase === 'play') {
          timeLeft -= dt;
          if (timeLeft <= 10 && timeLeft > 0 && Math.ceil(timeLeft) !== lastTick) {
            lastTick = Math.ceil(timeLeft);
            D.haptic('light'); D.tone({ freq: 880, dur: 0.04, type: 'square', vol: 0.04 });
          }
          if (timeLeft <= 0) { timeLeft = 0; phase = 'lost'; onLost(); }
          else if (delHeld) {
            delT += dt;
            if (delT > 0.42) { delT -= 0.09; if (typed > 0) { D.haptic('select'); backspace(); } }
          }
        }
        D.score(score);
      }
      for (r = 0; r < ROWS; r++) {
        row = rows[r];
        if (row.revealAt < 0 || row.done) continue;
        while (row.flipped < COLS && now >= row.revealAt + row.flipped * STAGGER + FLIP * 0.5) { onFlip(r, row.flipped); row.flipped++; }
        if (row.flipped === COLS && now >= row.revealAt + REVEAL_TOTAL) {
          row.done = true;
          if (row.solved) onSolved(r);
          else if (phase === 'lost' && loseAt < 0) onLost();
        }
      }
      if (stampAt >= 0 && !stampHit && now >= stampAt + 0.14) {
        stampHit = true; shakeAmp = 10;
        D.haptic('medium'); D.tone({ freq: 140, dur: 0.16, type: 'square', vol: 0.09, slide: 70 });
      }
      if (endAt >= 0 && !ended && now >= endAt) {
        ended = true;
        for (i = 0; i < L.keys.length; i++) L.keys[i].held = 0;
        holds = {}; delHeld = false;
        D.end({ score: score, unit: 'points', headline: headline });
      }
      if (dispScore !== score) {
        dispScore += (score - dispScore) * Math.min(1, dt * 12);
        if (Math.abs(score - dispScore) < 0.6) dispScore = score;
      }
      if (shakeAmp > 0.2) {
        shakeX = (Math.random() - 0.5) * 2 * shakeAmp; shakeY = (Math.random() - 0.5) * 2 * shakeAmp;
        shakeAmp *= Math.exp(-dt * 11);
      } else { shakeAmp = 0; shakeX = 0; shakeY = 0; }
      for (i = 0; i < particles.length; i++) {
        p = particles[i];
        if (!p.on) continue;
        p.life += dt;
        if (p.life >= p.max) { p.on = false; continue; }
        p.vy += 900 * dt; p.vx *= 1 - 1.6 * dt;
        p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.vr * dt;
      }
      for (i = 0; i < popups.length; i++) {
        p = popups[i];
        if (!p.on) continue;
        p.t += dt;
        if (p.t > (p.big ? 1.5 : 0.85)) p.on = false;
      }
    },

    draw: function (ctx, W, H, state) {
      if (!L || !rows) return;
      ctx.fillStyle = PAPER;
      ctx.fillRect(0, 0, W, H);
      ctx.save();
      if (shakeAmp) ctx.translate(shakeX, shakeY);
      ctx.drawImage(bg, 0, 0, W, H);
      drawHud(ctx, state);
      drawBoard(ctx, state);
      drawKeys(ctx);
      drawParticles(ctx);
      drawStamp(ctx);
      drawLoss(ctx);
      drawPopups(ctx);
      drawToast(ctx);
      if (state === 'ready' && !D.clip) drawHint(ctx);
      ctx.restore();
    },

    pointerDown: function (x, y, id) {
      var key = keyAt(x, y);
      if (!key) return;
      release(id);
      holds[id] = key;
      key.held++; key.downAt = now;
      if (key.k === 'DEL') { delHeld = true; delT = 0; }
      pressKey(key.k);
    },

    pointerMove: function () {},

    pointerUp: function (x, y, id) { release(id); },

    key: function (k) {
      if (k === 'Enter') tap('ENTER');
      else if (k === 'Backspace') tap('DEL');
      else if (k && k.length === 1 && /[a-zA-Z]/.test(k)) tap(k.toUpperCase());
    },

    bot: function (dt) {
      if (!botScript) return;
      botT += dt;
      while (botI < botScript.length && botT >= botScript[botI].d) {
        botT -= botScript[botI].d;
        tap(botScript[botI].k);
        botI++;
      }
    }
  });
})();
