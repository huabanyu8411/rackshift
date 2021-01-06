package io.rackshift.service;

import io.rackshift.model.InstructionDTO;
import io.rackshift.mybatis.domain.*;
import io.rackshift.mybatis.mapper.InstructionLogMapper;
import io.rackshift.mybatis.mapper.InstructionMapper;
import io.rackshift.utils.BeanUtils;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
public class InstructionService {
    @Resource
    private InstructionMapper instructionMapper;
    @Resource
    private InstructionLogMapper instructionLogMapper;
    @Resource
    private PluginService pluginService;
    @Resource
    private OutBandService outBandService;
    @Resource
    private DockerClientService dockerClientService;

    public Object add(InstructionDTO queryVO) {
        Instruction task = new Instruction();
        BeanUtils.copyBean(task, queryVO);

        instructionMapper.insertSelective(task);
        return true;
    }

    public Object update(Instruction queryVO) {
        instructionMapper.updateByPrimaryKeyWithBLOBs(queryVO);
        return true;
    }

    public Object del(String id) {
        Instruction task = instructionMapper.selectByPrimaryKey(id);
        if (task == null) return false;
        instructionMapper.deleteByPrimaryKey(id);
        return true;
    }

    public Object del(String[] ids) {
        for (String id : ids) {
            del(id);
        }
        return null;
    }

    public Object delLog(String[] ids) {
        for (String id : ids) {
            if(!delLog(id)){
                return false;
            }
        }
        return true;
    }

    public boolean delLog(String id) {
        instructionLogMapper.deleteByPrimaryKey(id);
        return true;
    }

    public List<Instruction> list(InstructionDTO queryVO) {
        return instructionMapper.selectByExampleWithBLOBs(buildExample(queryVO));
    }

    private InstructionExample buildExample(InstructionDTO queryVO) {
        return new InstructionExample();
    }


    public Instruction getById(String taskId) {
        return instructionMapper.selectByPrimaryKey(taskId);
    }

    public Object logs(String id) {
        InstructionLogExample e = new InstructionLogExample();
        e.createCriteria().andInstructionIdEqualTo(id);
        e.setOrderByClause("create_time asc");
        return instructionLogMapper.selectByExampleWithBLOBs(e);
    }

    public boolean runCommands(InstructionDTO instructionDTO) {
        if (StringUtils.isBlank(instructionDTO.getId()) || instructionDTO.getBareMetalIds().length == 0) {
            return false;
        }
        Instruction instruction = instructionMapper.selectByPrimaryKey(instructionDTO.getId());
        if (instruction == null) {
            return false;
        }

        Plugin plugin = pluginService.getById(instruction.getPluginId());

        if (plugin == null) {
            return false;
        }

        List<OutBand> outBands = outBandService.getByBareMetalIds(instructionDTO.getBareMetalIds());

        if (outBands.size() == 0) {
            return false;
        }

        outBands.forEach(o -> {
            dockerClientService.runWithContainer(buildCommand(o, plugin, instruction), plugin, instruction);
        });

        return true;
    }

    private List<Map<String, String>> buildCommand(OutBand o, Plugin plugin, Instruction instruction) {
        List<Map<String, String>> commands = new LinkedList<>();
        for (String s : instruction.getContent().split("\n")) {
            Map paramMap = new HashMap<String, String>();
            paramMap.put("image", plugin.getImage());
            paramMap.put("cmd", replaceVar(plugin.getBaseInstruction().trim(), o) + " " + s);
            commands.add(paramMap);
        }
        return commands;
    }

    private String replaceVar(String text, OutBand o) {
        Map<String, String> paramMap = buildMap(o);

        Pattern p = Pattern.compile("\\{\\{(\\w+)\\}\\}");
        Matcher m = p.matcher(text);

        while (m.find()) {
            text = text.replace(m.group(0), paramMap.get(m.group(1)));
        }
        return text;
    }

    private Map<String, String> buildMap(OutBand o) {

        Map map = new HashMap<String, String>();
        map.put("host", o.getIp());
        map.put("username", o.getUserName());
        map.put("password", o.getPwd());
        return map;
    }
}
