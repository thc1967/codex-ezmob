--- EZMobConfig
--- Central configuration module for EZMob parsers and importers.
---
--- Provides regular expressions and validation rules used to parse and interpret
--- stat blocks for monsters and malices in the MCDM system.
---
--- This module is registered globally using `RegisterGameType("EZMobConfig")` to allow
--- access from any other script file without explicit loading order dependencies.

--- @class EZMobConfig
EZMobConfig = RegisterGameType("EZMobConfig")
EZMobConfig.__index = EZMobConfig

EZMobConfig.regex = {}
EZMobConfig.regex.malice = {
    header = {
        name = "(?i)^(?<name>.+?)\\s+malice.*malice features$",
    },
    body = {
        ability = {
            name = "(?i)^\\s*(?<abilityName>[^0-9]+?)\\s+(?<malice>[0-9]+)\\+? Malice",
        },
    },
}
EZMobConfig.regex.monster = {}
EZMobConfig.regex.monster.legacy = {
    header = {
        name = "(?i)^(?<name>.*)\\s+(level|lvl) (?<level>[0-9]+)(?<minion> minion)? (?<role>.+)$",
        keywordsEv = "(?i)^(?<keywords>.*)\\s+ev (?<ev>[0-9]+)( for .+ minions)?$",
        stamina = "(?i)stamina.*?:?\\s*(?<stamina>[0-9]+)",
        immunities = "(?i).*immunity.*?:?\\s*(?<immunity>.*)$",
        weaknesses = "(?i).*weakness.*?:?\\s*(?<weakness>.*)$",
        speedSizeStability = "(?i)speed\\s*:?\\s*(?<speed>[0-9]+)(?:\\s+\\((?<moveType>[A-Za-z, ]+)\\))?\\s+size\\s*:?\\s*(?<size>[0-9]+[LMST]?)\\s*/\\s*stability\\s*:?\\s*(?<stability>[0-9]+|all)$", --"speed\\s*:?\\s*(?<speed>[0-9]+)\\s+\\(?(?<moveType>[A-Za-z, ]+)?\\)?\\s+size\\s*:?\\s*(?<size>[0-9]+[LMST]?)\\s*/\\s*stability\\s*:?\\s*(?<stability>[0-9]+|all)$",
        traitsFreeStrike = "(?i)^(with captain(?:\\s*:)?\\s*(?<withcaptain>.*?)\\s*)?free strike(?:\\s*:)?\\s*(?<freestrike>[0-9]+)$",
        characteristics = "(?i)^(?:might|mgt|m) \\+?(?<mgt>[0-9-]+)\\s*(?:agility|agl|a) \\+?(?<agl>[0-9+-]+)\\s*(?:reason|rea|r) \\+?(?<rea>[0-9+-]+)\\s*(?:intuition|inu|i) \\+?(?<inu>[0-9+-]+)\\s*(?:presence|prs|p) \\+?(?<prs>[0-9+-]+)$",
    },
    body = {
        ability = {
            name = "(?i)^(?<name>[^<]+)\\s*\\((?<action>action|main action|triggered action|maneuver|free action|free triggered action|villain action 1|villain action 2|villain action 3)\\).*?(?<signature>signature)?((?<vp>[0-9]+) (vp|malice))?$",
            roll = "(?i)^.*(?<roll>2d10\\s*[+-]\\s*[0-9]+).*$",
            rrAttribute = "(?i)makes?\\s+an?\\s+(?<stat>Might|Agility|Reason|Intuition|Presence|MGT|AGI|REA|INU|PRS|M|A|R|I|P)\\s+test", --"(?i)make?s?\\s+an?\\s+(?<stat>Might|MGT|M|Agility|AGI|A|Reason|REA|R|Intuition|INU|I|Presence|PRS|P)\\s+test",
            body = {
                keywords = "(?i)^keywords:?\\s+(?<description>.*)$",
                distanceTarget = "(?i)^distance:?\\s+(?<distance>(?:(?!\\s*target).)*?)\\s*(?:target:?\\s+(?<target>.*))?$",
                target = "(?i)^target:?\\s+(?<description>.*)$",
                rollTier1 = "(?i)^(?:(#diamond#|#sun#)\\s*(#lte#|<=)\\s*)?11\\s+(?<effect>.*)$",
                rollTier2 = "(?i)^(?:#star#\\s*)?12-16\\s+(?<effect>.*)$",
                rollTier3 = "(?i)^(?:(#diamond#|#sun#)\\s*)?17\\+?\\s+(?<effect>.*)$",
                effect = "(?i)^effect:?\\s+(?<description>.*)$",
                special = "(?i)^special:?\\s+(?<description>.*)$",
                trigger = "(?i)^trigger:?\\s+(?<description>.*)$",
                malice = "(?i)^(?<key>[0-9]+\\+?\\s+malice):?\\s+(?<description>.*)$",
            },
        },
        feature = { name = "^(?<name>[^:]+):\\s*(?<description>.+)$", },
    },
}

EZMobConfig.regex.monster.legacy.body.feature.enders = {
    EZMobConfig.regex.monster.legacy.header.name,
    EZMobConfig.regex.monster.legacy.body.ability.name,
    EZMobConfig.regex.monster.legacy.body.feature.name,
    EZMobConfig.regex.monster.legacy.body.ability.body.keywords,
    EZMobConfig.regex.monster.legacy.body.ability.body.distanceTarget,
    EZMobConfig.regex.monster.legacy.body.ability.body.target,
    EZMobConfig.regex.monster.legacy.body.ability.body.rollTier1,
    EZMobConfig.regex.monster.legacy.body.ability.body.rollTier2,
    EZMobConfig.regex.monster.legacy.body.ability.body.rollTier3,
    EZMobConfig.regex.monster.legacy.body.ability.body.effect,
    EZMobConfig.regex.monster.legacy.body.ability.body.special,
    EZMobConfig.regex.monster.legacy.body.ability.body.trigger,
    EZMobConfig.regex.monster.legacy.body.ability.body.malice,
}

EZMobConfig.regex.monster.retail = {
    header = {
        name = "(?i)^(?<name>.*)\\s+(level|lvl) (?<level>[0-9]+)(?<minion> minion)? (?<role>.+)$",
        keywordsEv = "(?i)^(?<keywords>.*)\\s+ev (?<ev>[0-9]+)( for .+ minions)?$",
        ssssfs = "(?i)^\\s*(?<size>[0-9]+[a-zA-Z]?)\\s+(?<speed>[0-9]+)\\s+(?<stamina>[0-9]+)\\s+(?<stability>[0-9]+)\\s+(?<freeStrike>[0-9]+)$",
        immunityWeakness = "(?i)^\\s*Immunity:\\s+(?<immunities>.*?)\\s+Weakness:\\s+(?<weaknesses>.*)$",
        movementCaptain = "(?i)^Movement:\\s*(?<movement>.*?)(?:\\s+With Captain:\\s*(?<withCaptain>.*?))?\\s*$",
        characteristics = "(?i)^(?:might|m\\s+ight|mgt|m) \\+?(?<mgt>[0-9-]+)\\s*(?:agility|a\\s+gility|agl|a) \\+?(?<agl>[0-9+-]+)\\s*(?:reason|r\\s+eason|rea|r) \\+?(?<rea>[0-9+-]+)\\s*(?:intuition|i\\s+ntuition|inu|i) \\+?(?<inu>[0-9+-]+)\\s*(?:presence|p\\s+resence|prs|p) \\+?(?<prs>[0-9+-]+)$",
    },
    body = {
        ability = {
            name = "(?i)^[abdmrs!]\\s+(?<name>.*?)(?=\\s+(?:\\d+d\\d+|Signature Ability|Villain Action|\\d+\\s+Malice)|$)(?:\\s+(?<roll>\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?))?(?:\\s+(?<signature>Signature Ability))?(?:\\s+Villain Action\\s+(?<villainAction>\\d+))?(?:\\s+(?<malice>\\d+)\\s+Malice)?\\s*$",
            body = {
                keywordsAction = "(?i)^(?<keywords>(?:[a-zA-Z]+|-)(?:,\\s*(?:[a-zA-Z]+|—))*)(?:\\s+(?<action>Free triggered action|Triggered action|Main action|Maneuver))?$",
                distanceTarget = "(?i)^e\\s+(?<distance>.*?)\\s+x\\s+(?<target>.*)$",
                effect = "(?i)^effect:?\\s+(?<description>.*)$",
                malice = "(?i)^(?<malice>\\d+\\+?\\s+Malice:)\\s+(?<description>.*)$",
                special = "(?i)^special:?\\s+(?<description>.*)$",
                trigger = "(?i)^trigger:?\\s+(?<description>.*)$",
                rollTier1 = "(?i)^(?:1|%C3%A1)\\s+(?!Malice:)(?<effect>.*)$",
                rollTier2 = "(?i)^(?:2|%C3%A9)\\s+(?!Malice:)(?<effect>.*)$",
                rollTier3 = "(?i)^(?:3|%C3%AD)\\s+(?!Malice:)(?<effect>.*)$",
            },
        },
        feature = { name = "(?i)^t\\s+(?<name>.*)$", },
        solo = {
            name = "(?i)^d\\s+(?<solo>(?!.*Villain Action\\s+\\d+$).*)$",
            feature = "^(?<name>[^:]+):\\s*(?<description>.+)$",
        },
    },
}

EZMobConfig.regex.monster.retail.body.feature.enders = {
    EZMobConfig.regex.monster.retail.header.name,
    EZMobConfig.regex.monster.retail.body.feature.name,
    EZMobConfig.regex.monster.retail.body.ability.name,
    EZMobConfig.regex.monster.retail.body.ability.body.keywordsAction,
    EZMobConfig.regex.monster.retail.body.ability.body.distanceTarget,
    EZMobConfig.regex.monster.retail.body.ability.body.effect,
    EZMobConfig.regex.monster.retail.body.ability.body.malice,
    EZMobConfig.regex.monster.retail.body.ability.body.special,
    EZMobConfig.regex.monster.retail.body.ability.body.trigger,
    EZMobConfig.regex.monster.retail.body.ability.body.rollTier1,
    EZMobConfig.regex.monster.retail.body.ability.body.rollTier2,
    EZMobConfig.regex.monster.retail.body.ability.body.rollTier3,
    EZMobConfig.regex.monster.retail.body.solo.feature,
}

EZMobConfig.regex.monster.validations = {
    distanceRange = "(?i)^(Range|Reach|Melee) (?<range>[0-9]+)$",
    numberedTargetsMatch = "(?i)(?<number>[0-9]+|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|A|An) (?<type>creature|creatures|ally|allies|enemy|enemies)( or objects?)?(of weight (?<weightRequirement>[0-9]+) or lower)?( per minion)?",
    meleeOrRangedMatch = "(?i)^Melee (?<melee>[0-9]+) or Ranged? (?<ranged>[0-9]+)",
    flatRangeCheck = "(?i)^\\s*(\\d+)\\s*$",
    cubeRangeCheck = "(?i)(?<radius>\\d+)\\s+cube within (?<range>\\d+)( squares?)?",
    lineMatchCheck = "(?i)(?<length>\\d+)\\s*by\\s*(?<width>\\d+)\\s*line within (?<range>\\d+)( squares?)?",
    burstMatchCheck = "(?i)(?<radius>\\d+)\\s*burst",
}

--- Validation constraints for monster import.
--- Includes known characteristic names and legal targeting patterns for range-checking.
--- @field validations table<string, table> Validation rules used for parsing
EZMobConfig.validations = {
    monster = {
        characteristics = { "mgt", "agl", "rea", "inu", "prs" },
        targetsForRangeCheck = {
            ["all allies in the burst"] = true,
            ["all allies"] = true,
            ["all creatures and objects in the burst"] = true,
            ["all creatures and objects"] = true,
            ["all creatures"] = true,
            ["all enemies and objects"] = true,
            ["all enemies in the burst"] = true,
            ["all enemies in the cube"] = true,
            ["all enemies"] = true,
            ["each ally"] = true,
            ["each creature in the area"] = true,
            ["each creature or object in the area"] = true,
            ["each creature"] = true,
            ["each enemy and object in each area"] = true,
            ["each enemy and object in the area"] = true,
            ["each enemy and object in the burst"] = true,
            ["each enemy in the area"] = true,
            ["each enemy in the cube"] = true,
            ["each enemy"] = true,
            ["self and each ally"] = true,
        },
        targetsForIgnoreCheck = {
            ["self"] = true,
            ["special"] = true,
        },
    },
};
