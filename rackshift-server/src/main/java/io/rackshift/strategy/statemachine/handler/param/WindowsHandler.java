package io.rackshift.strategy.statemachine.handler.param;

import com.alibaba.fastjson.JSONObject;
import io.rackshift.config.WorkflowConfig;
import io.rackshift.constants.ServiceConstants;
import io.rackshift.model.RSException;
import io.rackshift.mybatis.domain.Endpoint;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class WindowsHandler implements IOsParamHandler {
    @Resource
    WorkflowConfig workflowConfig;

    @Override
    public void process(JSONObject params) {
        List<Endpoint> endps = workflowConfig.getEndPoints();
        if (endps.size() > 0) {
            endps = endps.stream().filter(e -> ServiceConstants.EndPointType.main_endpoint.name().equalsIgnoreCase(e.getType())).collect(Collectors.toList());
            if (endps.size() > 0) {
                String winPeUrl = String.format("http://%s/common/winpe", endps.get(0).getIp());
                params.getJSONObject("options").getJSONObject("defaults").put("repo", winPeUrl);
            } else {
                RSException.throwExceptions("error:no main endpoints");
            }
        } else {
            RSException.throwExceptions("error:no endpoints");
        }

    }
}